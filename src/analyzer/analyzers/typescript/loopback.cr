require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/ts_decorator_extractor"
require "../../../utils/top_level_split"

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
    HTTP_VERBS            = {"GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "QUERY"}
    STRING_ARG            = /\A(['"`])([^'"`]*)\1\z/

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

      literal_values = extract_literal_values(content)
      classes = Noir::TsDecoratorExtractor.extract(content, path)

      process_classes(classes, content, path, result, include_callee, literal_values)
    rescue e : Exception
      logger.debug "Error analyzing LoopBack file #{path}: #{e.message}"
    end

    private def process_classes(classes : Array(Noir::TsDecoratorExtractor::ClassDecl), content : String,
                                file_path : String, result : Array(Endpoint), include_callee : Bool,
                                literal_values : Hash(String, Array(String)))
      classes.each do |klass|
        klass.methods.each do |method|
          routes = method.decorators.select do |decorator|
            decorator.called && (METHOD_MAP.has_key?(decorator.name) || decorator.name == "operation")
          end
          next if routes.empty?

          body = method_body(content, method)
          callees = nil

          routes.each do |route|
            route_verb_and_path = resolve_verb_and_path(route)
            next unless route_verb_and_path
            verb, path_expr = route_verb_and_path

            route_paths = literal_paths_from_expression(path_expr, literal_values)
            next unless route_paths

            decorator_line = route.row + 1

            if include_callee && body && callees.nil?
              callees = Noir::JSCalleeExtractor.callees_for_function_body(body, file_path, method.body_row + 1)
            end

            route_paths.each do |route_path|
              next if route_path.empty?
              url = route_path.starts_with?("/") ? route_path : "/#{route_path}"

              endpoint = Endpoint.new(url, verb)
              endpoint.details = Details.new(PathInfo.new(file_path, decorator_line))

              extract_path_parameters(url, endpoint)
              extract_decorator_parameters(method, endpoint)
              callees.try &.each do |name, callee_path, line|
                endpoint.push_callee(Callee.new(name, path: callee_path, line: line))
              end

              result << endpoint
            end
          end
        end
      end
    end

    private def method_body(content : String, method : Noir::TsDecoratorExtractor::Method) : String?
      start = method.body_start || return
      stop = method.body_end || return
      content.byte_slice(start, stop - start) if stop >= start
    end

    # `@get`/`@post`/`@put`/`@patch`/`@del` carry the path as their only
    # (first) argument. `@operation(verb, path, spec?)` is the generic
    # escape hatch — the HTTP verb is a string literal first argument.
    private def resolve_verb_and_path(decorator : Noir::TsDecoratorExtractor::Decorator) : Tuple(String, String)?
      if decorator.name == "operation"
        return unless decorator.args.size >= 2
        verb = extract_http_verb(decorator.args[0])
        return unless verb
        {verb, decorator.args[1]}
      else
        method = METHOD_MAP[decorator.name]?
        return unless method
        return if decorator.args.empty?
        {method, decorator.args[0]}
      end
    end

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
        endpoint.push_param(Param.new(param_name, "", "path"))
      end
    end

    private def extract_decorator_parameters(method : Noir::TsDecoratorExtractor::Method, endpoint : Endpoint)
      method.params.each do |param|
        param.decorators.each do |decorator|
          name = decorator.name

          if name.starts_with?("param.path.")
            if param_name = string_arg(decorator.args.first?)
              endpoint.push_param(Param.new(param_name, "", "path"))
            end
          elsif name.starts_with?("param.query.")
            if param_name = string_arg(decorator.args.first?)
              endpoint.push_param(Param.new(param_name, "", "query"))
            end
          elsif name.starts_with?("param.header.")
            if param_name = string_arg(decorator.args.first?)
              endpoint.push_param(Param.new(param_name, "", "header"))
            end
          elsif name == "param.array"
            if (param_name = string_arg(decorator.args.first?)) &&
               (location = string_arg(decorator.args[1]?)) &&
               ARRAY_PARAM_LOCATIONS.includes?(location)
              endpoint.push_param(Param.new(param_name, "", location))
            end
          elsif name == "requestBody" || name.starts_with?("requestBody.")
            endpoint.push_param(Param.new("body", "", "body"))
          end
        end
      end

      if method.decorators.any? { |d| d.name == "requestBody" || d.name.starts_with?("requestBody.") }
        endpoint.push_param(Param.new("body", "", "body"))
      end
    end

    private def string_arg(arg : String?) : String?
      val = arg.try(&.strip.match(STRING_ARG)).try(&.[2])
      val && !val.empty? ? val : nil
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
      Noir::TopLevelSplit.split(text, delimiter, Noir::TopLevelSplit::Rules::JS)
    end
  end
end
