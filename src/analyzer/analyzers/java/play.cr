require "../../../models/analyzer"
require "../../../miniparsers/java_callee_extractor"
require "../../../miniparsers/java_route_extractor_ts"

module Analyzer::Java
  class Play < Analyzer
    # Stores parsed controller methods with their parameters
    alias ControllerMethod = NamedTuple(headers: Array(String), cookies: Array(String), body_type: String?, callees: Array(Callee))
    alias ScopedKey = Tuple(String, String)

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile), so the name/receiver-specific matchers
    # below are memoized per interpolated value instead of being rebuilt
    # for every controller method.
    @action_name_regexes = Hash(String, Regex).new
    @request_param_regexes = Hash(Tuple(String, Symbol), Regex).new
    @body_type_regexes = Hash(String, Tuple(Regex, Regex, Regex, Regex)).new

    def analyze
      file_list = all_files()
      routes_files = [] of String
      java_files = [] of String

      # First pass: find all routes files and Java controller files
      file_list.each do |path|
        next unless File.exists?(path)
        # Skip test sources: Play's own repo parks `routes` files
        # under `dev-mode/sbt-plugin/src/sbt-test/...` (sbt-plugin
        # test fixtures) and `dev-mode/play-routes-compiler/src/test/
        # resources/`. Both `/src/test/` (Maven/Gradle convention) and
        # `/src/sbt-test/` (sbt-plugin's per-fixture test trees) are
        # unambiguous — production code never adopts either.
        next if path.includes?("/src/test/") || path.includes?("/src/sbt-test/")

        if path.ends_with?("routes") || path.ends_with?("routes.conf") || path.includes?("/conf/routes")
          routes_files << path
        elsif path.ends_with?(".java") && play_controller_file?(path)
          java_files << path
        end
      end

      # Parse controller files to build method map
      controller_methods = parse_controller_files(java_files)
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

    # Decide whether a `.java` file holds Play actions. The `controllers`
    # package is the conventional home, but Play resolves actions by the
    # fully-qualified name written in the `routes` file, so apps freely
    # park controllers under any package (e.g. `app/v1/post/
    # PostController.java` referenced as `v1.post.PostController.list`).
    # Gating on the `play.mvc` marker recovers those — without it their
    # body/header/cookie params and callees were silently dropped. The
    # per-method `play_action_method?` filter downstream keeps
    # non-action classes (filters, actions, helpers) from contributing.
    private def play_controller_file?(path : String) : Bool
      return true if path.includes?("/controllers/")
      read_file_content(path).includes?("play.mvc")
    end

    # Parse Java controller files to extract header, cookie, and body parameters
    private def parse_controller_files(java_files : Array(String)) : Hash(ScopedKey, ControllerMethod)
      controller_methods = Hash(ScopedKey, ControllerMethod).new
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      java_files.each do |path|
        content = read_file_content(path)
        base_path = configured_base_for(path)

        # Extract package name
        package_name = ""
        if pkg_match = content.match(/package\s+([\w.]+)\s*;/)
          package_name = pkg_match[1]
        end

        Noir::TreeSitter.parse_java(content) do |root|
          constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants_from(root, content)

          walk_class_declarations(root) do |class_decl|
            class_name = class_name_of(class_decl, content)
            next if class_name.empty?

            class_body = Noir::TreeSitter.field(class_decl, "body")
            next unless class_body

            Noir::TreeSitter.each_named_child(class_body) do |method|
              next unless Noir::TreeSitter.node_type(method) == "method_declaration"
              method_name = method_name_of(method, content)
              next if method_name.empty?
              next unless play_action_method?(method, method_name, content)
              full_method_name = package_name.empty? ? "#{class_name}.#{method_name}" : "#{package_name}.#{class_name}.#{method_name}"

              method_body_node = Noir::TreeSitter.field(method, "body")
              next unless method_body_node
              method_body = Noir::TreeSitter.node_text(method_body_node, content)

              request_receivers = request_receivers_for_method(method, content)
              headers = extract_request_params(method_body, request_receivers, constants, :header)
              cookies = extract_request_params(method_body, request_receivers, constants, :cookie)
              body_type = extract_body_type(method_body, request_receivers)

              callees = if include_callee
                          Noir::JavaCalleeExtractor.callees_in_body(method_body_node, content, path).map do |(name, callee_path, callee_line)|
                            Callee.new(name, path: callee_path, line: callee_line)
                          end
                        else
                          [] of Callee
                        end

              controller_methods[{base_path, full_method_name}] = {headers: headers, cookies: cookies, body_type: body_type, callees: callees}
            end
          end
        end
      end

      controller_methods
    end

    private def walk_class_declarations(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      ty = Noir::TreeSitter.node_type(node)
      block.call(node) if ty == "class_declaration"
      Noir::TreeSitter.each_named_child(node) do |child|
        walk_class_declarations(child, &block)
      end
    end

    private def class_name_of(class_decl : LibTreeSitter::TSNode, content : String) : String
      name = Noir::TreeSitter.field(class_decl, "name")
      name ? Noir::TreeSitter.node_text(name, content) : ""
    end

    private def method_name_of(method : LibTreeSitter::TSNode, content : String) : String
      name = Noir::TreeSitter.field(method, "name")
      name ? Noir::TreeSitter.node_text(name, content) : ""
    end

    private def play_action_method?(method : LibTreeSitter::TSNode, method_name : String, content : String) : Bool
      method_source = Noir::TreeSitter.node_text(method, content)
      return false unless method_source.match(/(?:public|protected)\s+(?:static\s+)?/)

      return_type = play_action_return_type(method, content)
      return false unless play_action_return_type?(return_type)

      name_regex = @action_name_regexes[method_name] ||= /\b#{Regex.escape(method_name)}\s*\(/
      !!method_source.match(name_regex)
    end

    private def play_action_return_type(method : LibTreeSitter::TSNode, content : String) : String
      if type = Noir::TreeSitter.field(method, "type")
        return Noir::TreeSitter.node_text(type, content)
      end

      ""
    end

    private def play_action_return_type?(return_type : String) : Bool
      normalized = return_type.gsub(/\s+/, "")
      return true if normalized == "Result" || normalized.ends_with?(".Result")

      !!(normalized =~ /(?:\A|\.)CompletionStage<(.+\.)?Result>/) ||
        !!(normalized =~ /(?:\A|\.)Promise<(.+\.)?Result>/)
    end

    private def request_receivers_for_method(method : LibTreeSitter::TSNode, content : String) : Array(String)
      receivers = ["request\\(\\)", "(?:Http\\s*\\.\\s*)?(?:Context\\s*\\.\\s*current\\(\\)\\s*\\.\\s*)?request\\(\\)"]
      params = Noir::TreeSitter.field(method, "parameters")
      return receivers unless params

      Noir::TreeSitter.each_named_child(params) do |param|
        next unless Noir::TreeSitter.node_type(param) == "formal_parameter"
        name_node = Noir::TreeSitter.field(param, "name")
        type_node = Noir::TreeSitter.field(param, "type")
        next unless name_node && type_node
        next unless request_type?(type_node, content)
        receivers << "\\b#{Regex.escape(Noir::TreeSitter.node_text(name_node, content))}\\b"
      end

      receivers.uniq
    end

    private def request_type?(type_node : LibTreeSitter::TSNode, content : String) : Bool
      type_text = Noir::TreeSitter.node_text(type_node, content)
      type_text == "Request" || type_text == "Http.Request" || type_text.ends_with?(".Request")
    end

    private def extract_request_params(method_body : String,
                                       request_receivers : Array(String),
                                       constants : Hash(String, String),
                                       kind : Symbol) : Array(String)
      params = [] of String
      method_pattern = case kind
                       when :header
                         "(?:header|getHeaders\\(\\)\\s*\\.\\s*get)"
                       when :cookie
                         "(?:cookie|cookies\\(\\)\\s*\\.\\s*get)"
                       else
                         return params
                       end

      request_receivers.each do |receiver|
        receiver_regex = @request_param_regexes[{receiver, kind}] ||= /#{receiver}\s*\.\s*#{method_pattern}\s*\(\s*([^),]+)\s*\)/
        method_body.scan(receiver_regex) do |match|
          next unless match.size > 1
          value = resolve_string_arg(match[1], constants)
          params << value if value && !params.includes?(value)
        end
      end

      params
    end

    private def extract_body_type(method_body : String, request_receivers : Array(String)) : String?
      request_receivers.each do |receiver|
        json_re, form_re, xml_re, raw_re = @body_type_regexes[receiver] ||= begin
          body = /#{receiver}\s*\.\s*body\(\)\s*\.\s*/
          {/#{body}(?:asJson|as\(\s*JsonNode)/,
           /#{body}(?:asFormUrlEncoded|asMultipartFormData)/,
           /#{body}asXml/,
           /#{body}as(?:Text|Raw|Bytes)/}
        end
        return "json" if method_body.match(json_re)
        return "form" if method_body.match(form_re)
        return "xml" if method_body.match(xml_re)
        return "body" if method_body.match(raw_re)
      end

      nil
    end

    private def resolve_string_arg(raw_arg : String, constants : Hash(String, String)) : String?
      arg = raw_arg.strip
      if arg.size >= 2 && ((arg.starts_with?('"') && arg.ends_with?('"')) || (arg.starts_with?("'") && arg.ends_with?("'")))
        return arg[1..-2]
      end

      if resolved = constants[arg]?
        return resolved
      end

      suffix = ".#{arg}"
      matches = constants.compact_map do |key, value|
        key.ends_with?(suffix) ? value : nil
      end.uniq!
      matches.size == 1 ? matches.first : nil
    end

    private def index_routes_files(routes_files : Array(String)) : Hash(ScopedKey, String)
      index = Hash(ScopedKey, String).new

      routes_files.each do |path|
        base_path = configured_base_for(path)
        basename = File.basename(path)
        index[{base_path, basename}] = path

        if basename == "routes" || basename == "routes.conf"
          index[{base_path, "Routes"}] = path
          index[{base_path, "router.Routes"}] = path
        elsif match = basename.match(/^(.+)\.routes$/)
          name = match[1]
          index[{base_path, name}] = path
          index[{base_path, "#{name}.Routes"}] = path
        end
      end

      index
    end

    private def collect_included_routes(routes_files : Array(String), routes_by_key : Hash(ScopedKey, String)) : Set(String)
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

    private def resolve_included_routes_file(target : String, routes_by_key : Hash(ScopedKey, String), including_path : String) : String?
      key = target.split(/\s|\(/).first.strip
      key = key.lchop("@")
      candidates = [key]
      base_path = configured_base_for(including_path)

      if key.ends_with?(".Routes")
        candidates << key[0...(key.size - ".Routes".size)]
      else
        candidates << "#{key}.Routes"
      end

      candidates.each do |candidate|
        scoped_key = {base_path, candidate}
        return routes_by_key[scoped_key] if routes_by_key.has_key?(scoped_key)
      end

      nil
    end

    # Process a Play routes file
    private def process_routes_file(path : String,
                                    controller_methods : Hash(ScopedKey, ControllerMethod),
                                    routes_by_key : Hash(ScopedKey, String),
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
          extract_controller_params(endpoint, action, controller_methods, path)

          @result << endpoint
        end
      end

      seen.delete(path)
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
    # Example: controllers.Users.show(id: Long, name: String)
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
          # `i` is a CHAR index; char-slice (byte_slice would treat i as a byte
          # offset and desync the match when a multi-byte char precedes it).
          return i if depth == 0 && text[i, operator.size] == operator
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
      normalized == "Request" || normalized == "Http.Request" || normalized.ends_with?(".Request")
    end

    # Extract header, cookie, and body parameters from controller method
    private def extract_controller_params(endpoint : Endpoint,
                                          action : String,
                                          controller_methods : Hash(ScopedKey, ControllerMethod),
                                          routes_path : String)
      # Extract controller method name from action
      # Example: controllers.Users.show(id: Long) -> controllers.Users.show
      method_name = action.split("(").first.strip.lchop("@")

      # Look up the controller method
      if method_info = controller_methods[{configured_base_for(routes_path), method_name}]?
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

        method_info[:callees].each do |callee|
          endpoint.push_callee(callee)
        end
      end
    end

    # Create an endpoint with the given path and method
    private def create_endpoint(path : String, method : String, source : String, line_number : Int32)
      details = Details.new(PathInfo.new(source, line_number))
      params = [] of Param

      Endpoint.new(path, method, params, details)
    end
  end
end
