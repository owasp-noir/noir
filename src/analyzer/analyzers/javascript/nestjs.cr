require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Javascript
  class Nestjs < JavascriptEngine
    def analyze
      analyze_with_extensions([".js", ".jsx"])
    end

    protected def analyze_with_extensions(extensions : Array(String)) : Array(Endpoint)
      result = [] of Endpoint
      static_dirs = [] of Hash(String, String)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      parallel_file_scan(extensions) do |path|
        analyze_nestjs_file(path, result, static_dirs, include_callee)
      end

      # Process static directories to create endpoints for static files
      process_static_dirs(static_dirs, result)

      result
    end

    # Process static directories and add endpoints for each file
    private def process_static_dirs(static_dirs : Array(Hash(String, String)), result : Array(Endpoint))
      static_dirs.each do |dir|
        full_path = (base_path + "/" + dir["file_path"]).gsub_repeatedly("//", "/")
        static_path = dir["static_path"]
        static_path = static_path[0..-2] if static_path.ends_with?("/") && static_path != "/"

        get_files_by_prefix(full_path).each do |file_path|
          if File.exists?(file_path)
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

    private def analyze_nestjs_file(path : String, result : Array(Endpoint), static_dirs : Array(Hash(String, String)), include_callee : Bool)
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end

        # Extract static paths
        Noir::JSRouteExtractor.extract_static_paths(content).each do |static_path|
          static_dirs << static_path unless static_dirs.any? { |s| s["static_path"] == static_path["static_path"] && s["file_path"] == static_path["file_path"] }
        end

        analyze_nestjs_controllers(content, path, result, include_callee)
      end
    rescue e : Exception
      logger.debug "Error analyzing NestJS file #{path}: #{e.message}"
    end

    private def analyze_nestjs_controllers(content : String, path : String, result : Array(Endpoint), include_callee : Bool)
      # Split content by controllers and process each separately
      controllers = extract_controllers(content)

      controllers.each do |controller_info|
        base_path = controller_info[:base_path]
        controller_content = controller_info[:content]
        controller_start_line = controller_info[:start_line]?.try(&.to_i) || 1

        process_http_methods(controller_content, base_path, path, result, include_callee, controller_start_line)
      end
    end

    private def extract_controllers(content : String)
      controllers = [] of Hash(Symbol, String)

      # Find all @Controller decorators and their associated class content
      lines = content.split("\n")
      current_controller : Hash(Symbol, String)? = nil
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
          base = parse_controller_decorator(joined[:text])
          if !base.nil?
            current_controller = {
              :base_path  => base,
              :content    => "",
              :start_line => "1",
            }
            skip_until = joined[:last_line]
            next if joined[:last_line] > index
          end
        end

        # Check for class start after @Controller
        if current_controller && line =~ /export\s+class\s+\w+/
          in_class = true
          brace_count = 0
          current_controller[:start_line] = (index + 1).to_s
        end

        # Count braces to find class end
        if in_class && current_controller
          brace_count += line.count('{')
          brace_count -= line.count('}')

          current_controller[:content] = current_controller[:content] + line + "\n"

          # End of class
          if brace_count == 0 && line.includes?('}')
            controllers << current_controller
            current_controller = nil
            in_class = false
          end
        end
      end

      controllers
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

    # Parse `@Controller(...)` and return the base path for the
    # routes it scopes. Recognized shapes:
    #
    #   @Controller()                              -> ""
    #   @Controller('users')                       -> "users"
    #   @Controller(`v1/users`)                    -> "v1/users"
    #   @Controller({ path: 'users' })             -> "users"
    #   @Controller({ path: 'users', version: 1 }) -> "users"
    #   @Controller({ version: 1, path: 'users' }) -> "users"
    #   @Controller(SOME_CONST)                    -> ""  (best-effort
    #     fallback: register the controller without a prefix rather
    #     than miss every route inside it.)
    #
    # Returns nil when `text` isn't a `@Controller(...)` decorator.
    private def parse_controller_decorator(text : String) : String?
      return unless text.includes?("@Controller")
      # Allow `(...)` to span newlines; the caller (`extract_controllers`)
      # already joined the multi-line header for us.
      match = text.match(/@Controller\s*\(([\s\S]*?)\)/m)
      return unless match
      inner = match[1].strip
      return "" if inner.empty?

      if str = inner.match(/^['"`]([^'"`]*)['"`]\s*$/)
        return str[1]
      end

      if inner.starts_with?("{")
        if obj = inner.match(/path\s*:\s*['"`]([^'"`]+)['"`]/)
          return obj[1]
        end
      end

      ""
    end

    private def process_http_methods(class_content : String, base_path : String, file_path : String, result : Array(Endpoint), include_callee : Bool, controller_start_line : Int32)
      http_methods = ["Get", "Post", "Put", "Delete", "Patch", "Options", "Head"]

      http_methods.each do |method|
        method_pattern = /@#{method}\s*\(\s*(?:['"`]([^'"`]*?)['"`]\s*)?\)/

        class_content.scan(method_pattern) do |match|
          route_path = ""
          if match.size > 1 && match[1]?
            route_path = match[1]
          end

          # Construct full URL path
          full_path = combine_paths(base_path, route_path)

          # Create endpoint
          endpoint = Endpoint.new(full_path, method.upcase)
          endpoint.details = Details.new(PathInfo.new(file_path, 1))

          # Extract path parameters from URL
          extract_path_parameters(full_path, endpoint)

          # Extract parameters from the method area
          if match.begin
            extract_method_parameters(class_content, match.begin + match[0].size, endpoint)
            attach_method_callees(class_content, match.begin + match[0].size, file_path, endpoint, controller_start_line) if include_callee
          end

          result << endpoint
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
      method_params.scan(/@Query\s*\(\s*['"`]([^'"`]+)['"`]\s*\)/) do |param_match|
        if param_match.size > 0
          param_name = param_match[1]
          endpoint.push_param(Param.new(param_name, "", "query"))
        end
      end

      # Extract @Param parameters (path parameters)
      method_params.scan(/@Param\s*\(\s*['"`]([^'"`]+)['"`]\s*\)/) do |param_match|
        if param_match.size > 0
          param_name = param_match[1]
          endpoint.push_param(Param.new(param_name, "", "path"))
        end
      end

      # Extract @Body() - indicates request body
      if method_params.includes?("@Body()")
        endpoint.push_param(Param.new("body", "", "body"))
      end

      # Extract @Headers parameters
      method_params.scan(/@Headers\s*\(\s*['"`]([^'"`]+)['"`]\s*\)/) do |param_match|
        if param_match.size > 0
          param_name = param_match[1]
          endpoint.push_param(Param.new(param_name, "", "header"))
        end
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
  end
end
