require "../../../models/analyzer"
require "../../../miniparsers/scala_callee_extractor"

module Analyzer::Scala
  class Play < Analyzer
    # Stores parsed controller methods with their parameters
    alias ControllerMethod = NamedTuple(headers: Array(String), cookies: Array(String), body_type: String?, callees: Array(Noir::ScalaCalleeExtractor::Entry))
    alias MethodBody = NamedTuple(signature: String, body: String)

    def analyze
      file_list = all_files()
      routes_files = [] of String
      scala_files = [] of String

      # First pass: find all routes files and Scala controller files
      file_list.each do |path|
        next unless File.exists?(path)
        # Skip test sources: Play's own repo parks ~300 phantom
        # endpoints in `dev-mode/sbt-plugin/src/sbt-test/.../conf/routes`
        # (sbt-plugin test fixtures) and `dev-mode/play-routes-compiler/
        # src/test/resources/*.routes`. Both `/src/test/` (Maven/Gradle
        # convention) and `/src/sbt-test/` (sbt-plugin's per-fixture
        # test trees) are unambiguous — production code never adopts
        # either.
        next if path.includes?("/src/test/") || path.includes?("/src/sbt-test/")

        if path.ends_with?("routes") || path.ends_with?("routes.conf") || path.includes?("/conf/routes")
          routes_files << path
        elsif path.ends_with?(".scala") && path.includes?("/controllers/")
          scala_files << path
        end
      end

      # Parse controller files to build method map
      controller_methods = parse_controller_files(scala_files)
      routes_by_key = index_routes_files(routes_files)
      included_routes = collect_included_routes(routes_files, routes_by_key)
      top_level_routes = routes_files.reject { |path| included_routes.includes?(path) }
      top_level_routes = routes_files if top_level_routes.empty?

      # Process each routes file
      top_level_routes.each do |routes_path|
        process_routes_file(routes_path, controller_methods, routes_by_key, "", Set(String).new)
      end

      Fiber.yield
      @result
    end

    # Parse Scala controller files to extract header, cookie, and body parameters
    private def parse_controller_files(scala_files : Array(String)) : Hash(String, ControllerMethod)
      controller_methods = Hash(String, ControllerMethod).new

      scala_files.each do |path|
        content = read_file_content(path)

        # Extract package name
        package_name = ""
        if pkg_match = content.match(/package\s+([\w.]+)/)
          package_name = pkg_match[1]
        end

        # Find all classes/objects in the file. Play controllers commonly carry
        # constructor injection before `extends`.
        class_regex = /(?:class|object)\s+(\w+)[^{}]*\{/
        class_matches = content.scan(class_regex)

        class_matches.each do |class_match|
          class_name = class_match[1]
          next if class_name.empty?

          # Find where this class starts
          class_start_idx = content.index(/(?:class|object)\s+#{Regex.escape(class_name)}/)
          next unless class_start_idx

          # Get content from class start
          class_content = content[class_start_idx..]

          # Find all def methods in the class. Route files decide whether a
          # method is externally reachable, so parsing custom ActionBuilder
          # wrappers here improves controller parameter enrichment without
          # adding standalone endpoints.
          method_regex = /def\s+(\w+)(?:\s*\([^)]*\))?(?:\s*:\s*[^=]+)?\s*=/
          class_content.scan(method_regex) do |match|
            method_name = match[1]
            full_method_name = package_name.empty? ? "#{class_name}.#{method_name}" : "#{package_name}.#{class_name}.#{method_name}"

            # Find the method body (from def to the matching closing brace)
            method = extract_method_body(class_content, method_name)
            next unless method

            method_body = method[:body]
            method_signature = method[:signature]

            headers = [] of String
            cookies = [] of String
            body_type : String? = nil

            # Extract headers: request.headers.get("Header-Name") or request.headers("Header-Name")
            method_body.scan(/request\s*\.\s*headers(?:\s*\.\s*get)?\s*\(\s*["']([^"']+)["']\s*\)/) do |header_match|
              headers << header_match[1] unless headers.includes?(header_match[1])
            end

            # Also match implicit request patterns: headers.get("Header-Name")
            method_body.scan(/headers\s*\.\s*get\s*\(\s*["']([^"']+)["']\s*\)/) do |header_match|
              headers << header_match[1] unless headers.includes?(header_match[1])
            end

            # Extract cookies: request.cookies.get("cookie-name")
            method_body.scan(/request\s*\.\s*cookies\s*\.\s*get\s*\(\s*["']([^"']+)["']\s*\)/) do |cookie_match|
              cookies << cookie_match[1] unless cookies.includes?(cookie_match[1])
            end

            # Also match: cookies.get("cookie-name")
            method_body.scan(/cookies\s*\.\s*get\s*\(\s*["']([^"']+)["']\s*\)/) do |cookie_match|
              cookies << cookie_match[1] unless cookies.includes?(cookie_match[1])
            end

            # Extract body type: request.body.asJson, request.body.asFormUrlEncoded, parse.json, parse.form
            body_source = "#{method_signature}\n#{method_body}"
            if body_source.match(/request\s*\.\s*body\s*\.\s*asJson|parse\s*\.\s*json|Json\s*\.\s*parse|\.body\s*\.\s*asJson/)
              body_type = "json"
            elsif body_source.match(/request\s*\.\s*body\s*\.\s*as(?:FormUrlEncoded|MultipartFormData)|parse\s*\.\s*form/)
              body_type = "form"
            elsif body_source.match(/request\s*\.\s*body\s*\.\s*asXml/)
              body_type = "xml"
            elsif body_source.match(/request\s*\.\s*body\s*\.\s*as(?:Text|Raw|Bytes)|parse\s*\.\s*text/)
              body_type = "body"
            end

            callees = callees_needed? ? Noir::ScalaCalleeExtractor.callees_for_body(method_body, path, line_number_for_method_body(content, class_start_idx, method_name)) : [] of Noir::ScalaCalleeExtractor::Entry
            controller_methods[full_method_name] = {headers: headers, cookies: cookies, body_type: body_type, callees: callees}
          end
        end
      end

      controller_methods
    end

    # Extract method body from content
    private def extract_method_body(content : String, method_name : String) : MethodBody?
      # Find method start and the first action block. Handles `Action`,
      # `Action.async`, parser variants, and custom action builders such as
      # `AuthenticatedAction { request => ... }`.
      method_start_regex = /def\s+#{Regex.escape(method_name)}(?:\s*\([^)]*\))?(?:\s*:\s*[^=]+)?\s*=/
      match = content.match(method_start_regex)
      return unless match

      search_start = match.end
      return unless search_start

      opening_brace = content.index('{', search_start)
      return unless opening_brace

      next_method = content.index(/\ndef\s+\w+/, search_start)
      return if next_method && next_method < opening_brace

      start_index = opening_brace + 1

      # Find matching closing brace
      brace_count = 1
      end_index = start_index
      while end_index < content.size && brace_count > 0
        case content[end_index]
        when '{'
          brace_count += 1
        when '}'
          brace_count -= 1
        end
        end_index += 1
      end

      signature_start = match.begin || 0
      signature = content[signature_start..opening_brace]
      body = content[start_index...end_index - 1]
      {signature: signature, body: body}
    end

    # Process a Play routes file
    private def process_routes_file(path : String,
                                    controller_methods : Hash(String, ControllerMethod),
                                    routes_by_key : Hash(String, Array(String)),
                                    prefix : String,
                                    seen : Set(String))
      return if seen.includes?(path)

      seen << path
      content = read_file_content(path)
      lines = content.split('\n')

      lines.each_with_index do |line, index|
        stripped_line = line.strip

        # Skip comments and empty lines
        next if stripped_line.empty? || stripped_line.starts_with?("#")

        if include_match = stripped_line.match(/^->\s+([^\s]+)\s+(.+)$/)
          include_prefix = include_match[1]
          include_target = include_match[2]
          if included_path = resolve_included_routes_file(include_target, routes_by_key, path)
            process_routes_file(included_path, controller_methods, routes_by_key, join_paths(prefix, include_prefix), seen)
          end
          next
        end

        # Match route definitions: METHOD /path controller.action
        # Example: GET /users/:id controllers.Users.show(id: Long)
        if route_match = stripped_line.match(/^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s+([^\s]+)\s+(.+)/)
          method = route_match[1]
          route_path = join_paths(prefix, route_match[2])
          action = route_match[3]

          endpoint = create_endpoint(route_path, method, path, index + 1)

          # Extract path parameters
          extract_path_params(endpoint, route_path)

          # Extract query parameters from action signature
          extract_params_from_action(endpoint, action)

          # Extract controller method name and add header/cookie/body params
          extract_controller_params(endpoint, action, controller_methods)

          @result << endpoint
        end
      end

      seen.delete(path)
    end

    private def index_routes_files(routes_files : Array(String)) : Hash(String, Array(String))
      index = Hash(String, Array(String)).new { |hash, key| hash[key] = [] of String }

      routes_files.each do |path|
        basename = File.basename(path)
        index[basename] << path

        if basename == "routes" || basename == "routes.conf"
          index["Routes"] << path
          index["router.Routes"] << path
        elsif match = basename.match(/^(.+)\.routes$/)
          name = match[1]
          index[name] << path
          index["#{name}.Routes"] << path
        end
      end

      index
    end

    private def collect_included_routes(routes_files : Array(String), routes_by_key : Hash(String, Array(String))) : Set(String)
      included = Set(String).new

      routes_files.each do |path|
        read_file_content(path).each_line do |line|
          stripped = line.strip
          next if stripped.empty? || stripped.starts_with?("#")
          next unless include_match = stripped.match(/^->\s+[^\s]+\s+(.+)$/)

          if included_path = resolve_included_routes_file(include_match[1], routes_by_key, path)
            included << included_path
          end
        end
      end

      included
    end

    private def resolve_included_routes_file(target : String,
                                             routes_by_key : Hash(String, Array(String)),
                                             including_path : String) : String?
      key = target.split(/\s|\(/).first.strip
      key = key.lchop("@")
      candidates = [key]

      if key.ends_with?(".Routes")
        candidates << key[0...(key.size - ".Routes".size)]
      else
        candidates << "#{key}.Routes"
      end

      including_dir = File.dirname(including_path)
      candidates.each do |candidate|
        paths = routes_by_key[candidate]?
        next unless paths

        if local_path = paths.find { |path| File.dirname(path) == including_dir }
          return local_path
        end
      end

      candidates.each do |candidate|
        paths = routes_by_key[candidate]?
        return paths.first if paths && paths.size == 1
      end

      nil
    end

    private def join_paths(prefix : String, suffix : String) : String
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end

    # Extract path parameters from route pattern
    private def extract_path_params(endpoint : Endpoint, route_path : String)
      # Match :param style parameters
      route_path.scan(/:(\w+)/) do |match|
        param_name = match[1]
        endpoint.push_param(Param.new(param_name, "", "path"))
      end

      # Match $param<regex> style parameters
      route_path.scan(/\$(\w+)<[^>]+>/) do |match|
        param_name = match[1]
        unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
          endpoint.push_param(Param.new(param_name, "", "path"))
        end
      end

      # Match *param wildcard style parameters
      route_path.scan(/\*(\w+)/) do |match|
        param_name = match[1]
        unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
          endpoint.push_param(Param.new(param_name, "", "path"))
        end
      end
    end

    # Extract query parameters from action signature
    # Example: controllers.Users.show(id: Long, name: String ?= "default")
    private def extract_params_from_action(endpoint : Endpoint, action : String)
      # Extract parameters from action signature
      if params_match = action.match(/\((.*)\)/)
        params_str = params_match[1]

        split_route_action_params(params_str).each do |param_def|
          param_def = param_def.strip
          next if param_def.empty?

          if route_param = route_action_param(param_def)
            param_name, param_type, default_value = route_param
            next if request_route_param_type?(param_type)
            next if endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
            next if endpoint.params.any? { |p| p.name == param_name }

            endpoint.push_param(Param.new(param_name, default_value, "query"))
          end
        end
      end
    end

    private def split_route_action_params(params_str : String) : Array(String)
      params = [] of String
      start = 0
      depth = 0
      in_string = false
      quote = '\0'
      escape = false

      params_str.each_char_with_index do |char, index|
        if in_string
          if escape
            escape = false
          elsif char == '\\'
            escape = true
          elsif char == quote
            in_string = false
          end
          next
        end

        case char
        when '"', '\''
          in_string = true
          quote = char
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        when ','
          next unless depth == 0

          params << params_str[start...index].strip
          start = index + 1
        end
      end

      tail = params_str[start..]?.to_s.strip
      params << tail unless tail.empty?
      params
    end

    private def route_action_param(param_def : String) : Tuple(String, String?, String)?
      optional_default_index = top_level_operator_index(param_def, "?=")
      fixed_value_index = top_level_operator_index(param_def, "=")
      return if fixed_value_index && optional_default_index.nil?

      declaration_end = optional_default_index || param_def.size
      declaration = param_def[0...declaration_end].strip
      return if declaration.empty?

      default_value = ""
      if optional_default_index
        raw_default = param_def[(optional_default_index + 2)..].strip
        default_value = normalize_route_default_value(raw_default)
      end

      if colon = declaration.index(':')
        name = declaration[0...colon].strip
        type_name = declaration[(colon + 1)..].strip
        return if name.empty?
        return {name, type_name.empty? ? nil : type_name, default_value}
      end

      name = declaration.strip
      return unless name.match(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
      {name, nil, default_value}
    end

    private def top_level_operator_index(text : String, operator : String) : Int32?
      depth = 0
      in_string = false
      quote = '\0'
      escape = false
      i = 0

      while i <= text.size - operator.size
        char = text[i]

        if in_string
          if escape
            escape = false
          elsif char == '\\'
            escape = true
          elsif char == quote
            in_string = false
          end
          i += 1
          next
        end

        case char
        when '"', '\''
          in_string = true
          quote = char
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        else
          return i if depth == 0 && text.byte_slice(i, operator.size) == operator
        end
        i += 1
      end

      nil
    end

    private def normalize_route_default_value(raw_default : String) : String
      value = raw_default.strip
      return "" if value.empty?

      if value.size >= 2 && ((value.starts_with?('"') && value.ends_with?('"')) || (value.starts_with?("'") && value.ends_with?("'")))
        return value[1..-2]
      end

      value
    end

    private def request_route_param_type?(param_type : String?) : Bool
      return false unless param_type

      normalized = param_type.gsub(/\s+/, "")
      normalized == "Request" || normalized == "RequestHeader" || normalized == "MessagesRequest" ||
        normalized.ends_with?(".Request") || normalized.ends_with?(".RequestHeader") || normalized.ends_with?(".MessagesRequest")
    end

    # Extract header, cookie, and body parameters from controller method
    private def extract_controller_params(endpoint : Endpoint, action : String, controller_methods : Hash(String, ControllerMethod))
      # Extract controller method name from action
      # Example: controllers.Users.show(id: Long) -> controllers.Users.show
      method_name = action.split("(").first.strip.lchop("@")

      # Look up the controller method
      if method_info = controller_methods[method_name]?
        # Add header parameters
        method_info[:headers].each do |header|
          unless endpoint.params.any? { |p| p.name == header && p.param_type == "header" }
            endpoint.push_param(Param.new(header, "", "header"))
          end
        end

        # Add cookie parameters
        method_info[:cookies].each do |cookie|
          unless endpoint.params.any? { |p| p.name == cookie && p.param_type == "cookie" }
            endpoint.push_param(Param.new(cookie, "", "cookie"))
          end
        end

        # Add body parameter if body type detected
        if body_type = method_info[:body_type]
          unless endpoint.params.any? { |p| p.name == "body" }
            endpoint.push_param(Param.new("body", "", body_type))
          end
        end

        method_info[:callees].each do |name, path, line|
          endpoint.push_callee(Callee.new(name, path: path, line: line))
        end
      end
    end

    private def line_number_for_method_body(content : String, class_start_idx : Int32, method_name : String) : Int32
      if method_start = content.index(/def\s+#{Regex.escape(method_name)}(?:\s*\([^)]*\))?(?:\s*:\s*[^=]+)?\s*=/, class_start_idx)
        return content[0, method_start].count('\n') + 1
      end

      1
    end

    # Create an endpoint with the given path and method
    private def create_endpoint(path : String, method : String, source : String, line_number : Int32)
      details = Details.new(PathInfo.new(source, line_number))
      params = [] of Param

      Endpoint.new(path, method, params, details)
    end
  end
end
