require "../../engines/rust_engine"

module Analyzer::Rust
  class Rwf < RustEngine
    # Look for route! macro calls and Controller implementations
    ROUTE_PATTERN = /route!\("([^"]+)"\s*=>\s*(\w+)\)/

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = read_file_content(path).lines
      include_callee = any_to_bool(@options["include_callee"]?)
      controller_bodies = collect_controller_handle_bodies(lines)

      lines.each_with_index do |line, index|
        # Look for route! macro definitions
        next unless line.includes? "route!("
        match = line.match(ROUTE_PATTERN)
        next unless match

        begin
          route_path = match[1]
          controller_name = match[2]
          details = Details.new(PathInfo.new(path, index + 1))

          # Extract HTTP methods supported by the controller
          controller_body = controller_bodies[controller_name]?
          methods = controller_body ? extract_controller_methods_from_body(controller_body[0]) : extract_controller_methods(lines, controller_name)

          # If no specific methods found, default to GET
          if methods.empty?
            methods = ["GET"]
          end

          # Create an endpoint for each HTTP method
          methods.each do |http_method|
            endpoint = Endpoint.new(route_path, http_method, details)

            # Extract path parameters from route pattern (e.g., /users/:id)
            extract_path_params(route_path, endpoint)

            # Look for controller implementation to extract more parameters
            if controller_body
              body, body_start_line = controller_body
              extract_controller_params_from_body(body, endpoint)
              attach_rust_callees(endpoint, Noir::RustCalleeExtractor.callees_for_body(body, path, body_start_line)) if include_callee
            else
              extract_controller_params(lines, controller_name, endpoint)
            end

            endpoints << endpoint
          end
        rescue
        end
      end

      endpoints
    end

    # Extract path parameters from the route pattern like /users/:id
    def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/:(\w+)/) do |match|
        param_name = match[1]
        endpoint.push_param(Param.new(param_name, "", "path"))
      end
    end

    private def collect_controller_handle_bodies(lines : Array(String)) : Hash(String, Tuple(String, Int32))
      controller_bodies = {} of String => Tuple(String, Int32)
      current_controller = nil
      in_block_comment = false
      index = 0

      while index < lines.size
        stripped, in_block_comment = Noir::RustCalleeExtractor.strip_comment_with_state(lines[index], in_block_comment)

        if match = stripped.match(/impl\s+Controller\s+for\s+([A-Za-z_]\w*)/)
          current_controller = match[1]
        elsif current_controller && stripped.strip.match(/^(?:async\s+)?fn\s+handle\b/)
          function_body = extract_rust_function_body_with_end(lines, index)
          if function_body
            body, body_start_line, end_index = function_body
            controller_bodies[current_controller] = {body, body_start_line}
            current_controller = nil
            index = end_index
            in_block_comment = false
          end
        end

        index += 1
      end

      controller_bodies
    end

    private def extract_controller_methods_from_body(body : String) : Array(String)
      methods = [] of String
      in_block_comment = false

      body.each_line do |raw_line|
        line, in_block_comment = strip_comments_preserving_strings(raw_line, in_block_comment)
        next unless line.includes?("Method::")

        ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"].each do |method|
          methods << method if line.includes?("Method::#{method}") && !methods.includes?(method)
        end
      end

      methods
    end

    private def extract_controller_params_from_body(body : String, endpoint : Endpoint)
      existing_path_params = endpoint.params.select { |p| p.param_type == "path" }.map(&.name).to_set
      in_block_comment = false

      body.each_line do |raw_line|
        line, in_block_comment = strip_comments_preserving_strings(raw_line, in_block_comment)

        if line.includes?("request.path_parameter")
          extract_typed_params(line, /request\.path_parameter/, endpoint, "path", existing_path_params)
        end

        if line.includes?("request.query_parameter")
          extract_typed_params(line, /request\.query_parameter/, endpoint, "query")
        end

        if line.includes?("request.body()")
          endpoint.push_param(Param.new("body", "", "json"))
        end

        if line.includes?("request.form_data()")
          endpoint.push_param(Param.new("form", "", "form"))
        end

        if line.includes?("request.header(")
          line.scan(/request\.header\("([^"]+)"\)/) do |match|
            endpoint.push_param(Param.new(match[1], "", "header"))
          end
        end

        if line.includes?("request.cookie(")
          line.scan(/request\.cookie\("([^"]+)"\)/) do |match|
            endpoint.push_param(Param.new(match[1], "", "cookie"))
          end
        end
      end
    end

    # Extract HTTP methods supported by the controller
    def extract_controller_methods(lines : Array(String), controller_name : String) : Array(String)
      methods = [] of String
      in_controller = false
      in_handle_method = false
      brace_count = 0
      seen_opening_brace = false

      lines.each do |line|
        # Check if we're entering the controller definition
        if line.includes?("struct #{controller_name}")
          in_controller = true
        end

        # Track if we're in the handle method
        if in_controller && (line.includes?("async fn handle") || line.includes?("fn handle"))
          in_handle_method = true
        end

        # Track braces to know when method ends
        if in_handle_method
          brace_count += line.count('{')
          if brace_count > 0
            seen_opening_brace = true
          end
          brace_count -= line.count('}')

          # Look for match request.method() pattern to detect supported methods
          if line.includes?("match request.method()")
            # Continue reading to find Method::GET, Method::POST, etc.
            next
          end

          # Extract HTTP methods from Method::GET, Method::POST, etc.
          if line.includes?("Method::")
            ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"].each do |method|
              if line.includes?("Method::#{method}")
                methods << method unless methods.includes?(method)
              end
            end
          end

          # Stop if we've moved past the method
          if seen_opening_brace && brace_count == 0
            in_handle_method = false
            in_controller = false
            break
          end
        end

        # Stop looking if we hit another struct definition
        if in_controller && line.strip.starts_with?("struct ") && !line.includes?(controller_name)
          in_controller = false
          break
        end
      end

      methods
    end

    # Extract parameters from controller implementation
    def extract_controller_params(lines : Array(String), controller_name : String, endpoint : Endpoint)
      # Find the controller struct and its handle method
      in_controller = false
      in_handle_method = false
      brace_count = 0
      seen_opening_brace = false
      # Track path parameters already added from route to avoid duplicates
      existing_path_params = endpoint.params.select { |p| p.param_type == "path" }.map(&.name).to_set

      lines.each do |line|
        # Check if we're entering the controller definition
        if line.includes?("struct #{controller_name}")
          in_controller = true
        end

        # Track if we're in the handle method
        if in_controller && (line.includes?("async fn handle") || line.includes?("fn handle"))
          in_handle_method = true
        end

        # Track braces to know when method ends
        if in_handle_method
          brace_count += line.count('{')
          if brace_count > 0
            seen_opening_brace = true
          end
          brace_count -= line.count('}')

          # Extract path parameters from request.path_parameter with or without type
          # Supports: request.path_parameter("id"), request.path_parameter::<i64>("id")
          if line.includes?("request.path_parameter")
            extract_typed_params(line, /request\.path_parameter/, endpoint, "path", existing_path_params)
          end

          # Extract query parameters from request.query_parameter()
          if line.includes?("request.query_parameter")
            extract_typed_params(line, /request\.query_parameter/, endpoint, "query")
          end

          # Extract body/JSON parameters from request.body()
          if line.includes?("request.body()")
            endpoint.push_param(Param.new("body", "", "json"))
          end

          # Extract form data from request.form_data()
          if line.includes?("request.form_data()")
            endpoint.push_param(Param.new("form", "", "form"))
          end

          # Extract headers from request.header()
          if line.includes?("request.header(")
            line.scan(/request\.header\("([^"]+)"\)/) do |match|
              header_name = match[1]
              endpoint.push_param(Param.new(header_name, "", "header"))
            end
          end

          # Extract cookies from request.cookie()
          if line.includes?("request.cookie(")
            line.scan(/request\.cookie\("([^"]+)"\)/) do |match|
              cookie_name = match[1]
              endpoint.push_param(Param.new(cookie_name, "", "cookie"))
            end
          end

          # Stop if we've moved past the method (brace count is back to 0 after we've seen an opening brace)
          if seen_opening_brace && brace_count == 0
            in_handle_method = false
            in_controller = false
            break
          end
        end

        # Stop looking if we hit another struct definition
        if in_controller && line.strip.starts_with?("struct ") && !line.includes?(controller_name)
          in_controller = false
          break
        end
      end
    end

    # Helper method to extract parameters with optional type annotations
    # Pattern: request.method_name("param") or request.method_name::<Type>("param")
    private def extract_typed_params(line : String, method_pattern : Regex, endpoint : Endpoint, param_type : String, existing_params : Set(String)? = nil)
      pattern = /#{method_pattern.source}(?:::<[^>]+>)?\("([^"]+)"\)/
      line.scan(pattern) do |match|
        param_name = match[1]
        # Only add if not already in existing params (for path parameters)
        next if existing_params && existing_params.includes?(param_name)
        endpoint.push_param(Param.new(param_name, "", param_type))
      end
    end

    private def strip_comments_preserving_strings(line : String, in_block_comment : Bool) : Tuple(String, Bool)
      in_string = false
      escaped = false
      index = 0
      stripped = String::Builder.new

      while index < line.size
        char = line[index]

        if in_block_comment
          if char == '*' && line[index + 1]? == '/'
            in_block_comment = false
            index += 1
          end
        elsif in_string
          stripped << char
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == '"'
            in_string = false
          end
        elsif char == '"'
          in_string = true
          stripped << char
        elsif char == '/' && line[index + 1]? == '/'
          return {stripped.to_s, in_block_comment}
        elsif char == '/' && line[index + 1]? == '*'
          in_block_comment = true
          index += 1
        else
          stripped << char
        end

        index += 1
      end

      {stripped.to_s, in_block_comment}
    end
  end
end
