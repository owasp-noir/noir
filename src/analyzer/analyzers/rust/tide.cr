require "../../engines/rust_engine"

module Analyzer::Rust
  class Tide < RustEngine
    def analyze_file(path : String) : Array(Endpoint)
      content = read_file_content(path)
      parse_tide_routes(content, path, any_to_bool(@options["include_callee"]?))
    end

    private def parse_tide_routes(content : String, file_path : String, include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint

      # Map function names to their content and callees for route handlers.
      functions_map, function_callees = extract_functions(content, file_path, include_callee)

      # Find .at() method calls with chained HTTP methods
      # Pattern: .at("/path").get(handler) or .at("/path").get(|_| async { ... })
      at_pattern = /\.at\s*\(\s*["']([^"']+)["']\s*\)\s*\.\s*(get|post|put|delete|patch|head|options)\s*\(/i

      content.scan(at_pattern) do |match|
        if match.size >= 3
          path = match[1]
          method = match[2].upcase

          # Extract the handler part - find content between parentheses
          match_end = match.end
          if match_end
            handler = extract_handler_from_position(content, match_end)

            # Parse path parameters (Tide uses :param syntax)
            params = [] of Param
            final_path = path.gsub(/:(\w+)/) do |param_match|
              param_name = param_match[1..-1] # Remove the ':'
              params << Param.new(param_name, "", "path")
              ":#{param_name}"
            end

            # Extract non-path parameters from handler function
            extract_handler_params(handler, functions_map, params)

            details = Details.new(PathInfo.new(file_path, 1))
            endpoint = Endpoint.new(final_path, method, params, details)
            attach_handler_callees(handler, function_callees, endpoint) if include_callee
            endpoints << endpoint
          end
        end
      end

      # Also look for app initialization and route definitions in separate variables
      # Pattern: let route = app.at("/path"); route.get(handler)
      route_var_pattern = /(\w+)\s*=\s*\w+\.at\s*\(\s*["']([^"']+)["']\s*\)/
      method_call_pattern = /(\w+)\s*\.\s*(get|post|put|delete|patch|head|options)\s*\(/i

      routes_map = {} of String => String

      # First pass: collect route variable assignments
      content.scan(route_var_pattern) do |match|
        if match.size >= 3
          var_name = match[1]
          path = match[2]
          routes_map[var_name] = path
        end
      end

      # Second pass: find method calls on route variables
      content.scan(method_call_pattern) do |match|
        if match.size >= 3
          var_name = match[1]
          method = match[2].upcase

          if routes_map.has_key?(var_name)
            path = routes_map[var_name]

            # Extract handler
            match_end = match.end
            handler = ""
            if match_end
              handler = extract_handler_from_position(content, match_end)
            end

            # Parse path parameters
            params = [] of Param
            final_path = path.gsub(/:(\w+)/) do |param_match|
              param_name = param_match[1..-1]
              params << Param.new(param_name, "", "path")
              ":#{param_name}"
            end

            # Extract non-path parameters from handler function
            extract_handler_params(handler, functions_map, params)

            details = Details.new(PathInfo.new(file_path, 1))
            endpoint = Endpoint.new(final_path, method, params, details)
            attach_handler_callees(handler, function_callees, endpoint) if include_callee
            endpoints << endpoint
          end
        end
      end

      endpoints
    rescue
      [] of Endpoint
    end

    # Extract handler content from position (after the opening parenthesis)
    private def extract_handler_from_position(content : String, start_pos : Int32) : String
      paren_count = 1
      i = start_pos

      while i < content.size && paren_count > 0
        char = content[i]
        if char == '('
          paren_count += 1
        elsif char == ')'
          paren_count -= 1
        end
        i += 1
      end

      content[start_pos...i - 1].strip
    rescue
      ""
    end

    # Extract function definitions and their bodies
    private def extract_functions(content : String, file_path : String, include_callee : Bool) : Tuple(Hash(String, String), Hash(String, Array(Noir::RustCalleeExtractor::Entry)))
      functions = {} of String => String
      function_callees = Hash(String, Array(Noir::RustCalleeExtractor::Entry)).new
      lines = content.lines
      in_block_comment = false
      index = 0

      while index < lines.size
        stripped, in_block_comment = Noir::RustCalleeExtractor.strip_comment_with_state(lines[index], in_block_comment)
        match = stripped.strip.match(/^(?:pub(?:\([^)]*\))?\s+)?async\s+fn\s+([A-Za-z_]\w*)\b/)

        if match
          fn_name = match[1]
          function_body = extract_rust_function_body_with_end(lines, index)

          if function_body
            body, body_start_line, end_index = function_body
            functions[fn_name] = body
            function_callees[fn_name] = Noir::RustCalleeExtractor.callees_for_body(body, file_path, body_start_line) if include_callee
            index = end_index
            in_block_comment = false
          end
        end

        index += 1
      end

      {functions, function_callees}
    end

    private def attach_handler_callees(handler : String,
                                       function_callees : Hash(String, Array(Noir::RustCalleeExtractor::Entry)),
                                       endpoint : Endpoint)
      handler_name = extract_handler_name(handler)
      return unless handler_name

      if callees = function_callees[handler_name]?
        attach_rust_callees(endpoint, callees)
      end
    end

    private def extract_handler_name(handler : String) : String?
      stripped = handler.strip
      return if stripped.starts_with?("|")

      match = stripped.match(/^(?:[A-Za-z_]\w*::)*([A-Za-z_]\w*)$/)
      match[1] if match
    end

    # Extract parameters from handler function
    private def extract_handler_params(handler : String, functions_map : Hash(String, String), params : Array(Param))
      # If handler is a function name, look it up
      fn_name = handler.gsub(/\|.*?\|/, "").strip
      fn_body = functions_map[fn_name]? || handler

      # Extract query parameters - req.query::<T>() or req.query()
      # Pattern: let query: SearchQuery = req.query()
      if fn_body.includes?("req.query")
        # Try to extract type from variable declaration
        query_match = fn_body.match(/let\s+\w+\s*:\s*(\w+)\s*=\s*req\.query/)
        if query_match
          param_name = query_match[1]
          params << Param.new(param_name, "", "query") unless param_exists?(params, param_name, "query")
        else
          # Fallback to generic name
          params << Param.new("query", "", "query") unless param_exists?(params, "query", "query")
        end
      end

      # Extract JSON body parameters - req.body_json::<T>() or req.body_json()
      # Pattern: let user: UserData = req.body_json().await
      if fn_body.includes?("req.body_json")
        body_match = fn_body.match(/let\s+\w+\s*:\s*(\w+)\s*=\s*req\.body_json/)
        if body_match
          param_name = body_match[1]
          params << Param.new(param_name, "", "json") unless param_exists?(params, param_name, "json")
        else
          # Fallback to generic name
          params << Param.new("body", "", "json") unless param_exists?(params, "body", "json")
        end
      end

      # Extract form body parameters - req.body_form::<T>() or req.body_form()
      # Pattern: let form: LoginForm = req.body_form().await
      if fn_body.includes?("req.body_form")
        form_match = fn_body.match(/let\s+\w+\s*:\s*(\w+)\s*=\s*req\.body_form/)
        if form_match
          param_name = form_match[1]
          params << Param.new(param_name, "", "form") unless param_exists?(params, param_name, "form")
        else
          # Fallback to generic name
          params << Param.new("form", "", "form") unless param_exists?(params, "form", "form")
        end
      end

      # Extract header parameters - req.header("name")
      fn_body.scan(/req\.header\("([^"]+)"\)/) do |match|
        if match.size > 1
          header_name = match[1]
          params << Param.new(header_name, "", "header") unless param_exists?(params, header_name, "header")
        end
      end

      # Extract cookie parameters - req.cookie("name")
      fn_body.scan(/req\.cookie\("([^"]+)"\)/) do |match|
        if match.size > 1
          cookie_name = match[1]
          params << Param.new(cookie_name, "", "cookie") unless param_exists?(params, cookie_name, "cookie")
        end
      end
    end

    # Check if parameter already exists
    private def param_exists?(params : Array(Param), name : String, param_type : String) : Bool
      params.any? { |p| p.name == name && p.param_type == param_type }
    end
  end
end
