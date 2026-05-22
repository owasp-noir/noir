require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Javascript
  class Nestjs < JavascriptEngine
    private struct GlobalPrefixExclude
      getter path : String
      getter method : String?

      def initialize(@path : String, @method : String? = nil)
      end
    end

    private struct GlobalPrefixConfig
      getter prefix : String
      getter excludes : Array(GlobalPrefixExclude)

      def initialize(@prefix : String, @excludes : Array(GlobalPrefixExclude))
      end
    end

    def analyze
      analyze_with_extensions([".js", ".jsx"])
    end

    protected def analyze_with_extensions(extensions : Array(String)) : Array(Endpoint)
      result = [] of Endpoint
      static_dirs = [] of Hash(String, String)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      global_prefix_holder = [] of GlobalPrefixConfig
      global_prefix_mutex = Mutex.new

      parallel_file_scan(extensions) do |path|
        analyze_nestjs_file(path, result, static_dirs, include_callee, global_prefix_holder, global_prefix_mutex)
      end

      # Process static directories to create endpoints for static files
      process_static_dirs(static_dirs, result)

      # Apply discovered global prefix (`app.setGlobalPrefix('api')`)
      # — the bootstrap call mounts every controller under that prefix.
      apply_global_prefix(result, global_prefix_holder.first?)

      result
    end

    # Prepend the discovered `app.setGlobalPrefix('api')` value to
    # every endpoint URL. Endpoints whose URL already starts with the
    # normalized prefix (e.g. controllers that hard-coded `/api/...`)
    # are left untouched so we don't double-prefix.
    private def apply_global_prefix(result : Array(Endpoint), config : GlobalPrefixConfig?)
      return unless config

      prefix = config.prefix
      return if prefix.empty?

      normalized = prefix.starts_with?("/") ? prefix : "/#{prefix}"
      normalized = normalized.chomp("/")
      return if normalized.empty?

      # `Endpoint` is a struct (value type), so the block-local
      # binding is a copy — write back through the index to make the
      # URL change visible to callers.
      result.each_with_index do |endpoint, idx|
        next if global_prefix_excluded?(endpoint, config.excludes)
        next if endpoint.url.starts_with?(normalized + "/") || endpoint.url == normalized
        endpoint.url = endpoint.url.starts_with?("/") ? "#{normalized}#{endpoint.url}" : "#{normalized}/#{endpoint.url}"
        result[idx] = endpoint
      end
    end

    private def global_prefix_excluded?(endpoint : Endpoint, excludes : Array(GlobalPrefixExclude)) : Bool
      excludes.any? do |exclude|
        next false if exclude.method && exclude.method != "ALL" && exclude.method != endpoint.method
        exclude_path_matches?(endpoint.url, exclude.path)
      end
    end

    private def exclude_path_matches?(url : String, exclude_path : String) : Bool
      normalized_url = normalize_path_for_prefix_exclude(url)
      normalized_exclude = normalize_path_for_prefix_exclude(exclude_path)

      if normalized_exclude.ends_with?("*")
        normalized_url.starts_with?(normalized_exclude.rstrip('*'))
      else
        normalized_url == normalized_exclude
      end
    end

    private def normalize_path_for_prefix_exclude(path : String) : String
      normalized = path.strip
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized = normalized.gsub_repeatedly("//", "/")
      normalized = normalized.chomp("/") unless normalized == "/"
      normalized
    end

    # Process static directories and add endpoints for each file
    private def process_static_dirs(static_dirs : Array(Hash(String, String)), result : Array(Endpoint))
      static_dirs.each do |dir|
        full_path = (base_path + "/" + dir["file_path"]).gsub_repeatedly("//", "/")
        static_path = dir["static_path"]
        static_path = static_path[0..-2] if static_path.ends_with?("/") && static_path != "/"

        get_files_by_prefix(full_path).each do |file_path|
          if File.file?(file_path)
            # Use lchop to only remove from the beginning of the string
            relative_path = file_path.starts_with?(full_path) ? file_path.lchop(full_path) : file_path
            url = static_path == "/" ? relative_path : "#{static_path}#{relative_path}"
            url = "/#{url}" unless url.starts_with?("/")

            details = Details.new(PathInfo.new(file_path))
            endpoint = Endpoint.new(url, "GET", details)
            result << endpoint unless result.any? { |e| e.url == url && e.method == "GET" }
          end
        end
      end
    end

    private def analyze_nestjs_file(path : String, result : Array(Endpoint), static_dirs : Array(Hash(String, String)), include_callee : Bool, global_prefix_holder : Array(GlobalPrefixConfig), global_prefix_mutex : Mutex)
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end

        # Extract static paths
        Noir::JSRouteExtractor.extract_static_paths(content).each do |static_path|
          static_dirs << static_path unless static_dirs.any? { |s| s["static_path"] == static_path["static_path"] && s["file_path"] == static_path["file_path"] }
        end

        # Strip JS/TS comments so commented-out decorators
        # (e.g. `// @Get('/old')`) don't generate phantom routes.
        sanitized = Noir::JSRouteExtractor.strip_js_comments(content)

        # `app.setGlobalPrefix('api')` in a bootstrap file scopes
        # every controller below it. Record it now; apply once after
        # all files have been parsed.
        if prefix = extract_global_prefix_config(sanitized)
          global_prefix_mutex.synchronize do
            global_prefix_holder << prefix if global_prefix_holder.empty?
          end
        end

        analyze_nestjs_controllers(sanitized, path, result, include_callee)
      end
    rescue e : Exception
      logger.debug "Error analyzing NestJS file #{path}: #{e.message}"
    end

    # Detect `app.setGlobalPrefix('api', { exclude: [...] })`.
    # Constants and dynamic expressions are ignored conservatively —
    # false-positive prefixing would mis-route every controller.
    private def extract_global_prefix_config(content : String) : GlobalPrefixConfig?
      literal_values = extract_literal_values(content)

      content.scan(/\.setGlobalPrefix\s*\(/) do |match|
        open_paren = (match.end(0) || 0) - 1
        next if open_paren < 0

        close_paren = Noir::JSRouteExtractor.find_matching_paren(content, open_paren)
        next unless close_paren

        args = split_top_level(content[(open_paren + 1)...close_paren], ',')
        next if args.empty?

        prefixes = literal_paths_from_expression(args[0], literal_values)
        next if prefixes.nil?
        next if prefixes.size != 1 || prefixes[0].empty?

        excludes = args.size > 1 ? extract_global_prefix_excludes(args[1], literal_values) : [] of GlobalPrefixExclude
        return GlobalPrefixConfig.new(prefixes[0], excludes)
      end
      nil
    end

    private def extract_global_prefix_excludes(options : String, literal_values : Hash(String, Array(String))) : Array(GlobalPrefixExclude)
      excludes = [] of GlobalPrefixExclude
      match = options.match(/\bexclude\s*:/)
      return excludes unless match

      idx = match.end(0)
      while idx < options.size && options[idx].whitespace?
        idx += 1
      end
      return excludes unless options[idx]? == '['

      close = find_matching_bracket(options, idx)
      return excludes unless close

      split_top_level(options[(idx + 1)...close], ',').each do |entry|
        excludes.concat(parse_global_prefix_exclude_entry(entry, literal_values))
      end
      excludes
    end

    private def parse_global_prefix_exclude_entry(entry : String, literal_values : Hash(String, Array(String))) : Array(GlobalPrefixExclude)
      stripped = entry.strip
      return [] of GlobalPrefixExclude if stripped.empty?

      paths = [] of String
      method : String? = nil

      if stripped.starts_with?("{")
        if path_match = stripped.match(/(?:^|[,{]\s*)path\s*:\s*([\s\S]*?)(?:,\s*\w+\s*:|\}\s*$)/m)
          paths = literal_paths_from_expression(path_match[1].strip, literal_values) || [] of String
        end

        if method_match = stripped.match(/\bmethod\s*:\s*(?:RequestMethod\.)?([A-Za-z]+)/)
          method = method_match[1].upcase
        end
      else
        paths = literal_paths_from_expression(stripped, literal_values) || [] of String
      end

      paths.map { |path| GlobalPrefixExclude.new(path, method) }
    end

    private def find_matching_bracket(text : String, open_idx : Int32) : Int32?
      depth = 0
      quote : Char? = nil
      escaped = false

      text.each_char_with_index do |char, idx|
        next if idx < open_idx

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
        when '['
          depth += 1
        when ']'
          depth -= 1
          return idx if depth == 0
        end
      end

      nil
    end

    private def analyze_nestjs_controllers(content : String, path : String, result : Array(Endpoint), include_callee : Bool)
      # Split content by controllers and process each separately
      literal_values = extract_literal_values(content)
      controllers = extract_controllers(content, literal_values)

      controllers.each do |controller_info|
        base_paths = controller_info[:base_paths]
        controller_content = controller_info[:content]
        controller_start_line = controller_info[:start_line]

        # Apply controller-level URI versioning. NestJS's default
        # `VersioningType.URI` prepends `v<n>` to the route, so
        # `@Controller({ path: 'cats', version: '1' })` becomes
        # `/v1/cats/...`. Header/Media-Type versioning leaves the URL
        # untouched — we conservatively emit the v-prefixed variant
        # since URI is the most common shape in OSS Nest apps.
        versions = controller_info[:versions]
        if !versions.empty?
          base_paths = expand_versions(base_paths, versions)
        end

        process_http_methods(controller_content, base_paths, path, result, include_callee, controller_start_line, literal_values)
      end
    end

    # Combine the controller's base paths with each version into a
    # set of `v<version>/<base>` paths. `'VERSION_NEUTRAL'` (Nest's
    # sentinel) is rendered as no prefix.
    private def expand_versions(base_paths : Array(String), versions : Array(String)) : Array(String)
      expanded = [] of String
      versions.each do |v|
        prefix = v == "VERSION_NEUTRAL" ? "" : "v#{v}"
        base_paths.each do |bp|
          if prefix.empty?
            expanded << bp
          elsif bp.empty?
            expanded << prefix
          else
            normalized = bp.starts_with?("/") ? bp[1..] : bp
            expanded << "#{prefix}/#{normalized}"
          end
        end
      end
      expanded.uniq
    end

    private def extract_controllers(content : String, literal_values : Hash(String, Array(String)))
      controllers = [] of NamedTuple(base_paths: Array(String), versions: Array(String), content: String, start_line: Int32)

      # Find all @Controller decorators and their associated class content
      lines = content.split("\n")
      current_base_paths : Array(String)? = nil
      current_versions : Array(String) = [] of String
      current_content = [] of String
      controller_start_line = 1
      brace_count = 0
      in_class = false
      skip_until = -1

      lines.each_with_index do |line, index|
        next if index <= skip_until

        # Detect any of NestJS's `@Controller` shapes. The
        # decorator header can span multiple lines (e.g.
        # `@Controller({\n  path: '...',\n  version: ...\n})`),
        # so coalesce continuation lines until the parens close
        # before parsing.
        if line.includes?("@Controller")
          joined = join_decorator_header(lines, index)
          base_paths = parse_controller_decorator(joined[:text], literal_values)
          if !base_paths.nil?
            current_base_paths = base_paths
            current_versions = parse_controller_versions(joined[:text])
            current_content.clear
            controller_start_line = 1
            skip_until = joined[:last_line]
            next if joined[:last_line] > index
          end
        end

        # Check for class start after @Controller
        if current_base_paths && line =~ /(?:export\s+)?(?:default\s+)?(?:abstract\s+)?class\s+\w+/
          in_class = true
          brace_count = 0
          controller_start_line = index + 1
        end

        # Count braces to find class end
        if in_class && current_base_paths
          brace_count += line.count('{')
          brace_count -= line.count('}')

          current_content << line

          # End of class
          if brace_count == 0 && line.includes?('}')
            controllers << {
              base_paths: current_base_paths,
              versions:   current_versions,
              content:    current_content.join("\n") + "\n",
              start_line: controller_start_line,
            }
            current_base_paths = nil
            current_versions = [] of String
            current_content.clear
            in_class = false
          end
        end
      end

      controllers
    end

    # Pull versions out of a `@Controller({ ..., version: ... })`
    # decorator. Recognized shapes:
    #   version: '1'                 -> ["1"]
    #   version: 1                   -> ["1"]
    #   version: ['1', '2']          -> ["1", "2"]
    #   version: VERSION_NEUTRAL     -> ["VERSION_NEUTRAL"]
    # When no `version:` key is present, returns an empty array
    # (meaning: leave the route URL untouched).
    private def parse_controller_versions(text : String) : Array(String)
      inner = decorator_inner(text, "Controller")
      return [] of String unless inner
      return [] of String unless inner.starts_with?("{")

      versions = [] of String

      # version: ['1', '2']
      if am = inner.match(/\bversion\s*:\s*\[([^\]]+)\]/)
        am[1].scan(/['"]([^'"]+)['"]/) do |m|
          versions << m[1] unless versions.includes?(m[1])
        end
        return versions unless versions.empty?
      end

      # version: '1' or version: "1"
      if sm = inner.match(/\bversion\s*:\s*['"]([^'"]+)['"]/)
        versions << sm[1]
        return versions
      end

      # version: 1 (numeric literal) or version: VERSION_NEUTRAL (identifier)
      if im = inner.match(/\bversion\s*:\s*([A-Za-z_][\w.]*|\d+)/)
        versions << im[1]
      end

      versions
    end

    # Coalesce a multi-line decorator header into a single string.
    # Starts at `start_idx`, advances until the running open-paren
    # count returns to zero. Returns the joined text plus the
    # index of the last consumed line.
    private def join_decorator_header(lines : Array(String), start_idx : Int32) : NamedTuple(text: String, last_line: Int32)
      text = lines[start_idx]
      depth = text.count('(') - text.count(')')
      idx = start_idx
      while depth > 0 && idx + 1 < lines.size
        idx += 1
        text += "\n" + lines[idx]
        depth += lines[idx].count('(') - lines[idx].count(')')
      end
      {text: text, last_line: idx}
    end

    # Parse `@Controller(...)` and return the base paths for the
    # routes it scopes. Recognized shapes:
    #
    #   @Controller()                              -> [""]
    #   @Controller('users')                       -> ["users"]
    #   @Controller(['users', 'admins'])           -> ["users", "admins"]
    #   @Controller({ path: 'users' })             -> ["users"]
    #   @Controller({ path: API.USERS })           -> ["users"]
    #   @Controller(SOME_CONST)                    -> [""]  (best-effort
    #     fallback: register the controller without a prefix rather
    #     than miss every route inside it.)
    #
    # Returns nil when `text` isn't a `@Controller(...)` decorator.
    private def parse_controller_decorator(text : String, literal_values : Hash(String, Array(String))) : Array(String)?
      return unless text.includes?("@Controller")
      # Allow `(...)` to span newlines; the caller (`extract_controllers`)
      # already joined the multi-line header for us.
      inner = decorator_inner(text, "Controller")
      return unless inner
      return [""] if inner.empty?

      literal_paths_from_expression(inner, literal_values) || [""]
    end

    private def decorator_inner(text : String, name : String) : String?
      decorator_idx = text.index("@#{name}")
      return unless decorator_idx

      open_paren = text.index("(", decorator_idx)
      return unless open_paren

      close_paren = Noir::JSRouteExtractor.find_matching_paren(text, open_paren)
      return unless close_paren

      text[(open_paren + 1)...close_paren].strip
    end

    private def extract_literal_values(content : String) : Hash(String, Array(String))
      literal_values = Hash(String, Array(String)).new

      content.scan(/\b(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*(['"`])([^'"`]*?)\2/) do |match|
        next unless match.size >= 4
        literal_values[match[1]] = [match[3]]
      end

      content.scan(/\benum\s+(\w+)\s*\{([\s\S]*?)\}/m) do |match|
        next unless match.size >= 3
        enum_name = match[1]
        body = match[2]
        body.scan(/(\w+)\s*=\s*(['"`])([^'"`]*?)\2/) do |member|
          next unless member.size >= 4
          literal_values["#{enum_name}.#{member[1]}"] = [member[3]]
        end
      end

      content.scan(/\b(?:export\s+)?const\s+(\w+)\s*=\s*\{([\s\S]*?)\}\s*(?:as\s+const)?/m) do |match|
        next unless match.size >= 3
        object_name = match[1]
        body = match[2]
        body.scan(/(?:['"`]?(\w+)['"`]?)\s*:\s*(['"`])([^'"`]*?)\2/) do |property|
          next unless property.size >= 4
          literal_values["#{object_name}.#{property[1]}"] = [property[3]]
        end
      end

      literal_values
    end

    private def literal_paths_from_expression(expression : String, literal_values : Hash(String, Array(String))) : Array(String)?
      expr = expression.strip
      return [""] if expr.empty?

      expr = expr.sub(/\s+as\s+const\s*$/, "").strip

      if str = expr.match(/^(['"`])([^'"`]*)\1$/)
        return [str[2]]
      end

      if expr.starts_with?("[") && expr.ends_with?("]")
        paths = [] of String
        split_top_level(expr[1...-1], ',').each do |part|
          resolved = literal_paths_from_expression(part, literal_values)
          resolved.try { |values| paths.concat(values) }
        end
        return paths unless paths.empty?
        return
      end

      if expr.starts_with?("{")
        if path_match = expr.match(/(?:^|[,{]\s*)path\s*:\s*([\s\S]*?)(?:,\s*\w+\s*:|\}\s*$)/m)
          path_expr = path_match[1].strip
          path_expr = path_expr[0...-1].strip if path_expr.ends_with?("}")
          return literal_paths_from_expression(path_expr, literal_values)
        end
        return
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

    private def process_http_methods(class_content : String, base_paths : Array(String), file_path : String, result : Array(Endpoint), include_callee : Bool, controller_start_line : Int32, literal_values : Hash(String, Array(String)))
      method_map = {
        "Get"     => ["GET"],
        "Post"    => ["POST"],
        "Put"     => ["PUT"],
        "Delete"  => ["DELETE"],
        "Patch"   => ["PATCH"],
        "Options" => ["OPTIONS"],
        "Head"    => ["HEAD"],
        # `@Sse` opens a Server-Sent Events stream — HTTP GET under
        # the hood, so it counts as a real route.
        "Sse" => ["GET"],
        "All" => ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"],
      }

      class_content.scan(/@(Get|Post|Put|Delete|Patch|Options|Head|Sse|All)\s*\(/) do |match|
        decorator_start = match.begin(0)
        next unless decorator_start

        method_name = match[1]
        methods = method_map[method_name]? || [] of String
        next if methods.empty?

        open_paren = class_content.index("(", decorator_start)
        next unless open_paren

        close_paren = Noir::JSRouteExtractor.find_matching_paren(class_content, open_paren)
        next unless close_paren

        route_paths = literal_paths_from_expression(class_content[(open_paren + 1)...close_paren].strip, literal_values)
        next unless route_paths

        # Resolve the decorator's line number inside the original
        # file: walk newlines from the class start to the
        # `class_content` offset where the decorator matched.
        decorator_line = controller_start_line + class_content[0...decorator_start].count('\n')

        base_paths.each do |base_path|
          route_paths.each do |route_path|
            full_path = combine_paths(base_path, route_path)
            methods.each do |method|
              endpoint = Endpoint.new(full_path, method)
              endpoint.details = Details.new(PathInfo.new(file_path, decorator_line))

              extract_path_parameters(full_path, endpoint)
              extract_method_parameters(class_content, close_paren + 1, endpoint)
              attach_method_callees(class_content, close_paren + 1, file_path, endpoint, controller_start_line) if include_callee

              result << endpoint
            end
          end
        end
      end
    end

    private def attach_method_callees(content : String, start_pos : Int32, file_path : String, endpoint : Endpoint, controller_start_line : Int32)
      body_info = extract_method_body(content, start_pos)
      return unless body_info

      body, open_brace_idx = body_info
      open_brace_line = controller_start_line + content[0...open_brace_idx].count('\n')
      language = file_path.ends_with?(".ts") || file_path.ends_with?(".tsx") ? :typescript : :javascript
      Noir::JSCalleeExtractor.callees_for_function_body(body, file_path, open_brace_line, language: language).each do |name, callee_path, line|
        endpoint.push_callee(Callee.new(name, path: callee_path, line: line))
      end
    end

    private def extract_method_body(content : String, start_pos : Int32) : Tuple(String, Int32)?
      method_section = content[start_pos..-1]
      method_name_match = method_section.match(/\s*(\w+)\s*\(/)
      return unless method_name_match

      start_paren = start_pos + method_name_match.end
      end_paren = Noir::JSRouteExtractor.find_matching_paren(content, start_paren - 1)
      return unless end_paren

      open_brace_idx = content.index("{", end_paren)
      return unless open_brace_idx

      close_brace_idx = Noir::JSRouteExtractor.find_matching_brace(content, open_brace_idx)
      return unless close_brace_idx && close_brace_idx > open_brace_idx

      {content[(open_brace_idx + 1)...close_brace_idx], open_brace_idx}
    end

    private def extract_method_parameters(content : String, start_pos : Int32, endpoint : Endpoint)
      # Find the method signature that immediately follows the decorator
      method_section = content[start_pos..-1]

      # Look for the method name first
      method_name_match = method_section.match(/\s*(\w+)\s*\(/)

      if method_name_match
        start_paren = method_name_match.end

        # Find the matching closing parenthesis for the method parameters
        paren_count = 1
        end_paren = start_paren
        method_section[start_paren..-1].each_char_with_index do |char, index|
          case char
          when '('
            paren_count += 1
          when ')'
            paren_count -= 1
            if paren_count == 0
              end_paren = start_paren + index
              break
            end
          end
        end

        if end_paren > start_paren
          method_params = method_section[start_paren...end_paren]
          extract_decorator_parameters(method_params, endpoint)
        end
      end
    end

    private def extract_decorator_parameters(method_params : String, endpoint : Endpoint)
      # Extract @Query parameters
      method_params.scan(/@Query\s*\(\s*['"`]([^'"`]+)['"`][\s\S]*?\)/) do |param_match|
        if param_match.size > 0
          param_name = param_match[1]
          push_unique_param(endpoint, Param.new(param_name, "", "query"))
        end
      end
      if method_params =~ /@Query\s*\(\s*(?:\)|[^'"`][\s\S]*?\))/
        push_unique_param(endpoint, Param.new("query", "", "query"))
      end

      # Extract @Param parameters (path parameters)
      method_params.scan(/@Param\s*\(\s*['"`]([^'"`]+)['"`][\s\S]*?\)/) do |param_match|
        if param_match.size > 0
          param_name = param_match[1]
          push_unique_param(endpoint, Param.new(param_name, "", "path"))
        end
      end

      # Extract @Body('field') and @Body() / @Body(pipe)
      method_params.scan(/@Body\s*\(\s*['"`]([^'"`]+)['"`][\s\S]*?\)/) do |body_match|
        if body_match.size > 0
          push_unique_param(endpoint, Param.new(body_match[1], "", "body"))
        end
      end

      if method_params =~ /@Body\s*\(\s*(?:\)|[^'"`][\s\S]*?\))/
        push_unique_param(endpoint, Param.new("body", "", "body"))
      end

      # Extract @Headers parameters
      method_params.scan(/@Headers\s*\(\s*['"`]([^'"`]+)['"`][\s\S]*?\)/) do |param_match|
        if param_match.size > 0
          param_name = param_match[1]
          push_unique_param(endpoint, Param.new(param_name, "", "header"))
        end
      end
      if method_params =~ /@Headers\s*\(\s*(?:\)|[^'"`][\s\S]*?\))/
        push_unique_param(endpoint, Param.new("headers", "", "header"))
      end

      # `@HostParam('account')` — subdomain capture when the controller
      # uses `@Controller({ host: ':account.example.com' })`.
      method_params.scan(/@HostParam\s*\(\s*['"`]([^'"`]+)['"`][\s\S]*?\)/) do |param_match|
        push_unique_param(endpoint, Param.new(param_match[1], "", "path")) if param_match.size > 0
      end

      # `@UploadedFile('field')` / `@UploadedFiles('field')` — multer
      # integration. Unnamed forms get a generic 'file' / 'files' body
      # param so consumers still see the upload surface.
      method_params.scan(/@UploadedFile\s*\(\s*['"`]([^'"`]+)['"`][\s\S]*?\)/) do |param_match|
        push_unique_param(endpoint, Param.new(param_match[1], "", "body")) if param_match.size > 0
      end
      if method_params =~ /@UploadedFile\s*\(\s*\)/
        push_unique_param(endpoint, Param.new("file", "", "body"))
      end

      method_params.scan(/@UploadedFiles\s*\(\s*['"`]([^'"`]+)['"`][\s\S]*?\)/) do |param_match|
        push_unique_param(endpoint, Param.new(param_match[1], "", "body")) if param_match.size > 0
      end
      if method_params =~ /@UploadedFiles\s*\(\s*\)/
        push_unique_param(endpoint, Param.new("files", "", "body"))
      end
    end

    private def combine_paths(base : String, route : String) : String
      return route if base.empty?
      return base if route.empty?

      base = base.chomp("/")
      route = route.starts_with?("/") ? route : "/#{route}"

      "#{base}#{route}"
    end

    private def extract_path_parameters(url : String, endpoint : Endpoint)
      # Extract path parameters from URL patterns like :id
      url.scan(/:(\w+)/) do |match|
        if match.size > 0
          param_name = match[1]
          # Only add if not already added by @Param decorator
          unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
            endpoint.push_param(Param.new(param_name, "", "path"))
          end
        end
      end
    end

    private def push_unique_param(endpoint : Endpoint, param : Param)
      return if endpoint.params.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
      endpoint.push_param(param)
    end
  end
end
