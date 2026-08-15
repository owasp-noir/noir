require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Typescript
  # LoopBack 4 (`@loopback/rest`) routes controller methods with OpenAPI
  # decorators applied directly to the method — `@get('/users/{id}')`,
  # `@post('/users')`, `@put`, `@patch`, `@del` (LB4's name for DELETE),
  # plus the generic `@operation('get', '/path')`. Unlike NestJS there is
  # no mandatory class-level `@Controller('prefix')`: every decorator
  # already carries the endpoint's full path, so — unlike the NestJS
  # analyzer this one is modeled on — there is no controller/base-path
  # composition step. `@api({basePath: ...})` is the one (rarely used)
  # exception; it is not resolved here (see the class doc at the bottom).
  class Loopback < Analyzer::Javascript::JavascriptEngine
    analyzer_for "ts_loopback"

    METHOD_MAP = {
      "get"   => "GET",
      "post"  => "POST",
      "put"   => "PUT",
      "patch" => "PATCH",
      "del"   => "DELETE",
    }

    # Request-body param types accepted by `@param.array('name', 'query'|'path'|'header', ...)`.
    ARRAY_PARAM_LOCATIONS = {"query", "path", "header"}

    def analyze
      result = [] of Endpoint
      include_callee = callees_needed?

      parallel_file_scan([".ts", ".tsx", ".cts", ".mts"]) do |path|
        next if ignored_loopback_path?(path)
        analyze_loopback_file(path, result, include_callee)
      end

      result
    end

    private def ignored_loopback_path?(path : String) : Bool
      # Scan-base-relative, never absolute: a `__tests__/` or `test/`
      # directory ABOVE the scan base is not this project's test tree.
      relative = base_relative_path(path)
      relative.includes?(".test.") || relative.includes?(".spec.") ||
        relative.includes?("/__tests__/") || relative.includes?("/__mocks__/") ||
        relative.includes?("/test/fixtures/") || relative.includes?("/tests/fixtures/")
    end

    # Precompiled once — a single PCRE2-JIT scan replaces eight naive
    # String#includes? substring scans over the whole file content.
    #
    # `from '@loopback/rest'` (not `import.*from ['"]@loopback\/rest['"]`)
    # so a multi-line import block — the shape the `lb4` CLI scaffolder
    # actually emits (`import {\n  get,\n  post,\n} from '@loopback/rest';`)
    # — still matches: `.` never spans a newline in Crystal regex, but the
    # closing `from '<module>'` is always on one line.
    LOOPBACK_IMPORT_RE = Regex.union(
      /from\s*['"]@loopback\/rest['"]/,
      /from\s*['"]@loopback\/core['"]/,
      /require\(\s*['"]@loopback\/rest['"]\s*\)/,
      /require\(\s*['"]@loopback\/core['"]\s*\)/,
    )

    # Guard every file individually against a genuine `@loopback/*`
    # import before scanning for `@get`/`@post`/... decorators. LoopBack
    # and NestJS share decorator *shape* but not decorator *case*
    # (`@get` vs `@Get`) or import source, and this file-level gate keeps
    # a neighboring TypeScript project in the same repo — one that
    # happens to define its own lowercase `@get(...)` decorator — from
    # being misread as LoopBack routes.
    private def loopback_source?(content : String) : Bool
      content.matches?(LOOPBACK_IMPORT_RE)
    end

    private def analyze_loopback_file(path : String, result : Array(Endpoint), include_callee : Bool)
      content = read_file_content(path)
      return unless loopback_source?(content)

      # Strip JS/TS comments so commented-out decorators
      # (e.g. `// @get('/old')`) don't generate phantom routes.
      sanitized = Noir::JSRouteExtractor.strip_js_comments(content)
      literal_values = extract_literal_values(sanitized)

      process_http_methods(sanitized, path, result, include_callee, literal_values)
    rescue e : Exception
      logger.debug "Error analyzing LoopBack file #{path}: #{e.message}"
    end

    private def process_http_methods(content : String, file_path : String, result : Array(Endpoint), include_callee : Bool, literal_values : Hash(String, Array(String)))
      content.scan(/@(get|post|put|patch|del|operation)\s*\(/) do |match|
        decorator_start = match.begin(0)
        next unless decorator_start

        decorator_name = match[1]

        open_paren = content.index("(", decorator_start)
        next unless open_paren

        close_paren = Noir::JSRouteExtractor.find_matching_paren(content, open_paren)
        next unless close_paren

        args = split_top_level(content[(open_paren + 1)...close_paren], ',')
        next if args.empty?

        route_verb_and_path = resolve_verb_and_path(decorator_name, args)
        next unless route_verb_and_path
        method, path_expr = route_verb_and_path

        route_paths = literal_paths_from_expression(path_expr, literal_values)
        next unless route_paths

        signature = method_signature_after_decorators(content, close_paren + 1)
        next unless signature

        decorator_line = 1 + content[0...decorator_start].count('\n')

        route_paths.each do |route_path|
          next if route_path.empty?
          url = route_path.starts_with?("/") ? route_path : "/#{route_path}"

          endpoint = Endpoint.new(url, method)
          endpoint.details = Details.new(PathInfo.new(file_path, decorator_line))

          extract_path_parameters(url, endpoint)
          extract_decorator_parameters(signature[:params], endpoint)
          attach_method_callees_from_signature(content, signature, file_path, endpoint) if include_callee

          result << endpoint
        end
      end
    end

    # `@get`/`@post`/`@put`/`@patch`/`@del` carry the path as their only
    # (first) argument. `@operation(verb, path, spec?)` is the generic
    # escape hatch — the HTTP verb is a string literal first argument.
    private def resolve_verb_and_path(decorator_name : String, args : Array(String)) : Tuple(String, String)?
      if decorator_name == "operation"
        return unless args.size >= 2
        verb = extract_http_verb(args[0])
        return unless verb
        {verb, args[1]}
      else
        method = METHOD_MAP[decorator_name]?
        return unless method
        return if args.empty?
        {method, args[0]}
      end
    end

    HTTP_VERBS = {"GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "QUERY"}

    private def extract_http_verb(expr : String) : String?
      match = expr.strip.match(/^['"`](\w+)['"`]$/)
      return unless match

      verb = match[1].upcase
      verb = "DELETE" if verb == "DEL"
      HTTP_VERBS.includes?(verb) ? verb : nil
    end

    # LoopBack path templates use OpenAPI-style `{id}` placeholders
    # (not Express-style `:id`).
    private def extract_path_parameters(url : String, endpoint : Endpoint)
      url.scan(/\{(\w+)\}/) do |match|
        param_name = match[1]
        push_unique_param(endpoint, Param.new(param_name, "", "path"))
      end
    end

    private def extract_decorator_parameters(method_params : String, endpoint : Endpoint)
      # `@param.path.string('id')`, `@param.path.number('id')`, ...
      method_params.scan(/@param\.path\.\w+\s*\(\s*['"`]([^'"`]+)['"`]/) do |m|
        push_unique_param(endpoint, Param.new(m[1], "", "path"))
      end

      # `@param.query.string('name')`, `@param.query.object('filter', ...)`, ...
      method_params.scan(/@param\.query\.\w+\s*\(\s*['"`]([^'"`]+)['"`]/) do |m|
        push_unique_param(endpoint, Param.new(m[1], "", "query"))
      end

      # `@param.header.string('x-token')`, ...
      method_params.scan(/@param\.header\.\w+\s*\(\s*['"`]([^'"`]+)['"`]/) do |m|
        push_unique_param(endpoint, Param.new(m[1], "", "header"))
      end

      # `@param.array('names', 'query', {type: 'string'})` — explicit location as 2nd arg.
      method_params.scan(/@param\.array\s*\(\s*['"`]([^'"`]+)['"`]\s*,\s*['"`](\w+)['"`]/) do |m|
        location = m[2]
        push_unique_param(endpoint, Param.new(m[1], "", location)) if ARRAY_PARAM_LOCATIONS.includes?(location)
      end

      # `@requestBody()`, `@requestBody({...})`, `@requestBody.array()`,
      # `@requestBody.file()` — LB4 always binds the whole request body to
      # a single method parameter (never a per-field name), so this maps
      # to one generic `body` param, matching the NestJS `@Body()` (no
      # field name) convention.
      if method_params =~ /@requestBody\b/
        push_unique_param(endpoint, Param.new("body", "", "body"))
      end
    end

    private def method_signature_after_decorators(content : String, start_pos : Int32)
      idx = skip_decorators_and_whitespace(content, start_pos)
      section = content[idx..-1]
      match = section.match(/\A\s*(?:(?:public|private|protected|static|async|readonly|override)\s+)*([A-Za-z_$][\w$]*)\s*\(/)
      return unless match

      open_paren = idx + match.end(0) - 1
      close_paren = Noir::JSRouteExtractor.find_matching_paren(content, open_paren)
      return unless close_paren

      open_brace = content.index("{", close_paren)
      return unless open_brace
      close_brace = Noir::JSRouteExtractor.find_matching_brace(content, open_brace)

      {
        name:        match[1],
        params:      content[(open_paren + 1)...close_paren],
        start_pos:   idx,
        open_paren:  open_paren,
        close_paren: close_paren,
        open_brace:  open_brace,
        close_brace: close_brace,
      }
    end

    # A LoopBack route decorator is often followed by more decorators
    # before the method itself — `@authenticate('jwt')`,
    # `@authorize({...})`, custom ones — so walk forward over any
    # `@word(...)` / `@word` sequence, same as NestJS's guard/interceptor
    # stacking.
    private def skip_decorators_and_whitespace(content : String, start_pos : Int32) : Int32
      idx = start_pos
      # `content[i]` re-decodes UTF-8 from byte 0 on every call once the
      # string isn't single_byte_optimizable? (any non-ASCII char), making
      # this O(n^2) when walked once per route decorator in a large
      # non-ASCII controller class. Index a pre-materialized Char array
      # instead — same semantics, O(1) lookup.
      chars = content.chars
      loop do
        while idx < chars.size && chars[idx].whitespace?
          idx += 1
        end
        break if idx >= chars.size || chars[idx] != '@'

        name_end = idx + 1
        while name_end < chars.size && (chars[name_end].alphanumeric? || chars[name_end] == '_' || chars[name_end] == '$' || chars[name_end] == '.')
          name_end += 1
        end

        scan = name_end
        while scan < chars.size && chars[scan].whitespace?
          scan += 1
        end

        if scan < chars.size && chars[scan] == '('
          close = Noir::JSRouteExtractor.find_matching_paren(content, scan)
          break unless close
          idx = close + 1
        else
          newline = content.index('\n', scan)
          idx = newline ? newline + 1 : chars.size
        end
      end
      idx
    end

    private def body_from_signature(content : String, signature) : Tuple(String, Int32)?
      close_brace = signature[:close_brace]
      return unless close_brace
      open_brace = signature[:open_brace]
      return unless close_brace > open_brace
      {content[(open_brace + 1)...close_brace], open_brace}
    end

    private def attach_method_callees_from_signature(content : String, signature, file_path : String, endpoint : Endpoint)
      body_info = body_from_signature(content, signature)
      return unless body_info

      body, open_brace_idx = body_info
      open_brace_line = 1 + content[0...open_brace_idx].count('\n')
      language = file_path.ends_with?(".ts") || file_path.ends_with?(".tsx") ? :typescript : :javascript
      Noir::JSCalleeExtractor.callees_for_function_body(body, file_path, open_brace_line, language: language).each do |name, callee_path, line|
        endpoint.push_callee(Callee.new(name, path: callee_path, line: line))
      end
    end

    private def extract_literal_values(content : String) : Hash(String, Array(String))
      literal_values = Hash(String, Array(String)).new

      content.scan(/\b(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*(['"`])([^'"`]*?)\2/) do |match|
        next unless match.size >= 4
        literal_values[match[1]] = [match[3]]
      end

      literal_values
    end

    private def literal_paths_from_expression(expression : String, literal_values : Hash(String, Array(String))) : Array(String)?
      expr = expression.strip
      return [""] if expr.empty?

      if str = expr.match(/^(['"`])([^'"`]*)\1$/)
        return [str[2]]
      end

      plus_parts = split_top_level(expr, '+')
      if plus_parts.size > 1
        pieces = [] of String
        plus_parts.each do |part|
          values = literal_paths_from_expression(part, literal_values)
          return unless values && values.size == 1
          pieces << values[0]
        end
        return [pieces.join]
      end

      literal_values[expr]?
    end

    private def split_top_level(text : String, delimiter : Char) : Array(String)
      parts = [] of String
      start = 0
      paren_depth = 0
      bracket_depth = 0
      brace_depth = 0
      quote : Char? = nil
      escaped = false

      text.each_char_with_index do |char, index|
        if quote
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            quote = nil
          end
          next
        end

        case char
        when '\'', '"', '`'
          quote = char
        when '('
          paren_depth += 1
        when ')'
          paren_depth -= 1 if paren_depth > 0
        when '['
          bracket_depth += 1
        when ']'
          bracket_depth -= 1 if bracket_depth > 0
        when '{'
          brace_depth += 1
        when '}'
          brace_depth -= 1 if brace_depth > 0
        else
          if char == delimiter && paren_depth == 0 && bracket_depth == 0 && brace_depth == 0
            parts << text[start...index].strip
            start = index + 1
          end
        end
      end

      parts << text[start..-1].strip
      parts.reject(&.empty?)
    end

    private def push_unique_param(endpoint : Endpoint, param : Param)
      return if endpoint.params.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
      endpoint.push_param(param)
    end
  end
end
