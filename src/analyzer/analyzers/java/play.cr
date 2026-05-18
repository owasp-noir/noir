require "../../../models/analyzer"
require "../../../miniparsers/java_callee_extractor"

module Analyzer::Java
  class Play < Analyzer
    # Stores parsed controller methods with their parameters
    alias ControllerMethod = NamedTuple(headers: Array(String), cookies: Array(String), body_type: String?, callees: Array(Callee))

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
        elsif path.ends_with?(".java") && path.includes?("/controllers/")
          java_files << path
        end
      end

      # Parse controller files to build method map
      controller_methods = parse_controller_files(java_files)

      # Process each routes file
      routes_files.each do |routes_path|
        process_routes_file(routes_path, controller_methods)
      end

      Fiber.yield
      @result
    end

    # Parse Java controller files to extract header, cookie, and body parameters
    private def parse_controller_files(java_files : Array(String)) : Hash(String, ControllerMethod)
      controller_methods = Hash(String, ControllerMethod).new
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      java_files.each do |path|
        content = read_file_content(path)

        # Extract package name
        package_name = ""
        if pkg_match = content.match(/package\s+([\w.]+)\s*;/)
          package_name = pkg_match[1]
        end

        Noir::TreeSitter.parse_java(content) do |root|
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

              headers = [] of String
              cookies = [] of String
              body_type : String? = nil

              # Extract headers: request().header("Header-Name") or request().getHeaders().get("Header-Name")
              method_body.scan(/request\(\)\s*\.\s*(?:header|getHeaders\(\)\s*\.\s*get)\s*\(\s*["']([^"']+)["']\s*\)/) do |header_match|
                headers << header_match[1] unless headers.includes?(header_match[1])
              end

              # Also match Http.Context.current().request().header("Header-Name")
              method_body.scan(/(?:Http\s*\.\s*)?(?:Context\s*\.\s*current\(\)\s*\.\s*)?request\(\)\s*\.\s*header\s*\(\s*["']([^"']+)["']\s*\)/) do |header_match|
                headers << header_match[1] unless headers.includes?(header_match[1])
              end

              # Extract cookies: request().cookie("cookie-name") or request().cookies().get("cookie-name")
              method_body.scan(/request\(\)\s*\.\s*(?:cookie|cookies\(\)\s*\.\s*get)\s*\(\s*["']([^"']+)["']\s*\)/) do |cookie_match|
                cookies << cookie_match[1] unless cookies.includes?(cookie_match[1])
              end

              # Extract body type
              if method_body.match(/request\(\)\s*\.\s*body\(\)\s*\.\s*(?:asJson|as\(\s*JsonNode)/)
                body_type = "json"
              elsif method_body.match(/request\(\)\s*\.\s*body\(\)\s*\.\s*(?:asFormUrlEncoded|asMultipartFormData)/)
                body_type = "form"
              elsif method_body.match(/request\(\)\s*\.\s*body\(\)\s*\.\s*asXml/)
                body_type = "xml"
              elsif method_body.match(/request\(\)\s*\.\s*body\(\)\s*\.\s*as(?:Text|Raw|Bytes)/)
                body_type = "body"
              end

              callees = if include_callee
                          Noir::JavaCalleeExtractor.callees_in_body(method_body_node, content, path).map do |(name, callee_path, callee_line)|
                            Callee.new(name, path: callee_path, line: callee_line)
                          end
                        else
                          [] of Callee
                        end

              controller_methods[full_method_name] = {headers: headers, cookies: cookies, body_type: body_type, callees: callees}
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
      !!method_source.match(/(?:public|protected)\s+(?:Result|CompletionStage<Result>)\s+#{Regex.escape(method_name)}\s*\(/)
    end

    # Process a Play routes file
    private def process_routes_file(path : String, controller_methods : Hash(String, ControllerMethod))
      content = File.read(path)
      lines = content.split('\n')

      lines.each_with_index do |line, index|
        stripped_line = line.strip

        # Skip comments and empty lines
        next if stripped_line.empty? || stripped_line.starts_with?("#")

        # Match route definitions: METHOD /path controller.action
        # Example: GET /users/:id controllers.Users.show(id: Long)
        if route_match = stripped_line.match(/^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s+([^\s]+)\s+(.+)/)
          method = route_match[1]
          route_path = route_match[2]
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

        # Split by comma for simple parsing (note: doesn't handle nested structures perfectly)
        params_str.split(',').each do |param_def|
          param_def = param_def.strip
          next if param_def.empty?

          # Skip named parameters with literal values (e.g., path="/public")
          # But don't skip optional parameters with defaults (e.g., name: String = "default")
          next if param_def.match(/^\w+\s*=\s*"/)

          # Extract parameter name and type
          # Formats: "id: Long", "name: String", "count: Integer"
          # Match parameter name followed by colon and any type
          if param_match = param_def.match(/^(\w+)\s*:\s*/)
            param_name = param_match[1]

            # Check if it's already a path parameter
            is_path_param = endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }

            unless is_path_param
              # Add as query parameter
              unless endpoint.params.any? { |p| p.name == param_name }
                endpoint.push_param(Param.new(param_name, "", "query"))
              end
            end
          end
        end
      end
    end

    # Extract header, cookie, and body parameters from controller method
    private def extract_controller_params(endpoint : Endpoint, action : String, controller_methods : Hash(String, ControllerMethod))
      # Extract controller method name from action
      # Example: controllers.Users.show(id: Long) -> controllers.Users.show
      method_name = action.split("(").first.strip

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
