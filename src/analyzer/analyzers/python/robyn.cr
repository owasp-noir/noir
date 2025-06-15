require "../python"
require "../../models/endpoint"
require "json"

module Analyzer
  module Python
    class Robyn < Analyzer::Python::Python
      def initialize(options = {} of String => String)
        super(options)
        @name = "python_robyn"
        @version = "0.0.1"
        @results = [] of Models::Endpoint
      end

      # Analyzes Python files for Robyn framework usage and extracts API endpoints.
      #
      # Args:
      #   base_path: The root directory to scan for Python files.
      def analyze(base_path : String)
        Dir.glob("#{base_path}/**/*.py").each do |file_path|
          next if File.directory?(file_path)
          # TODO: Add more robust virtualenv path skipping
          next if file_path.includes?("site-packages") || file_path.includes?("/.venv/") || file_path.includes?("/venv/")

          content = File.read(file_path, encoding: "utf-8", invalid: :skip)
          lines = content.lines

          lines.each_with_index do |line, line_num|
            # Decorator syntax: @app.get("/path") or @app.get(r"/path")
            # Example: @app.get("/")
            # Example: @app.post("/submit", another_arg=value)
            # Example: @app.patch(r"/items/:id")
            # Matches: @app.method(path), @app.method(path, ...), @app.method(r"path"), @app.method("path", ...)
            decorator_match = line.match(/@app\.(#{HTTP_METHODS.join("|")})\s*\(\s*(r?['"])(.*?)\2\s*(?:,|\))/)
            if decorator_match
              http_method = decorator_match[1].upcase
              route_path = decorator_match[3]
              # Handler function is expected to be defined on the next lines
              handler_def_line_index = line_num + 1
              # parse_decorated_function returns parent's FunctionDefinition's params
              parent_func_def = parse_decorated_function(lines, handler_def_line_index, file_path)

              if parent_func_def
                add_endpoint(file_path, line_num + 1, http_method, route_path, parent_func_def.params, parent_func_def.name)
              end
            end

            # add_route syntax: app.add_route(method="GET", endpoint="/path", handler=func_name)
            # Example: app.add_route(method="POST", endpoint="/data", handler=my_handler_function)
            # Robyn requires method, endpoint, and handler.
            add_route_match = line.match(/app\.add_route\s*\(\s*method\s*=\s*['"](#{HTTP_METHODS.join("|")})['"]\s*,\s*endpoint\s*=\s*(r?['"])(.*?)\3\s*,\s*handler\s*=\s*([a-zA-Z_][a-zA-Z0-9_]*)/i)
            if add_route_match
                http_method = add_route_match[1].upcase # Now mandatory
                route_path = add_route_match[3]
                handler_name = add_route_match[4]

                # Find the handler function definition in the current file
                # This is a simplified search; a more robust solution would involve full AST parsing
                # or at least a more context-aware search.
                func_def_content = ""
                func_def_start_line = -1
                lines.each_with_index do |l, i|
                    if l.match(/^\s*def\s+#{handler_name}\s*\(/)
                        func_def_content = lines[i..-1].join("\n")
                        func_def_start_line = i + 1 # 1-based
                        break
                    end
                end

                if func_def_content.empty?
                    # logger.warn "Handler function #{handler_name} not found for route #{route_path} in #{file_path}" # Assuming logger is available
                    next
                end

                parent_func_def = parse_function_def_from_lines(lines, handler_name, file_path)

                if parent_func_def
                  add_endpoint(file_path, line_num + 1, http_method, route_path, parent_func_def.params, handler_name)
                else
                  # logger.warn "Handler function #{handler_name} not found for route #{route_path} in #{file_path}"
                end
            end
          end
        end
      end

      # Parses a function definition given its name by searching through the file lines.
      # Returns Analyzer::Python::Python::FunctionDefinition | Nil
      private def parse_function_def_from_lines(lines : Array(String), handler_name : String, file_path : String)
        func_def_start_index = -1
        lines.each_with_index do |line_content, i|
          # Regex to match "def function_name(...)" or "async def function_name(...)"
          if line_content.match(/^\s*(async\s+)?def\s+#{Regex.escape(handler_name)}\s*\(/)
            func_def_start_index = i
            break
          end
        end

        return nil if func_def_start_index == -1

        # The parse_function_def from parent class expects index relative to the start of its input `lines`
        # and the lines array itself.
        # We pass all lines and the identified start index.
        return super(lines, func_def_start_index)
      end

      # Parses a function definition that is expected to immediately follow a decorator.
      # Returns Analyzer::Python::Python::FunctionDefinition | Nil
      private def parse_decorated_function(lines : Array(String), decorator_line_index : Int32, file_path : String)
        # Find the 'def' keyword after the decorator line index
        func_def_start_index = -1

        (decorator_line_index...lines.size).each do |i|
          line_content = lines[i]
          if line_content.match?(/^\s*(async\s+)?def/)
            func_def_start_index = i
            break
          end
          # If we encounter another decorator or a non-empty, non-comment line
          # that isn't the start of our function, then it's not directly decorated as expected.
          if line_content.strip.starts_with?("@") || (line_content.strip != "" && !line_content.match?(/^\s*#/) && i > decorator_line_index)
            return nil
          end
        end

        return nil if func_def_start_index == -1

        # Pass all lines and the identified start index of 'def'
        return super(lines, func_def_start_index)
      end

      private def add_endpoint(file_path : String, line_num : Int32, http_method : String, route_path : String, func_params_from_parent : Array(Analyzer::Python::Python::FunctionParameter), handler_name : String? = nil)
        path_params_from_route = extract_path_params_from_route(route_path)

        api_params = [] of Models::Parameter

        func_params_from_parent.each do |p|
          is_path_param = path_params_from_route.includes?(p.name)
          api_params << Models::Parameter.new(
            name: p.name,
            param_type: is_path_param ? "path" : "query", # Default non-path to query
            required: p.default.empty?, # Required if no default value
            value_type: p.type, # Type hint from parent parser
            default_value: p.default.empty? ? nil : p.default # Store default value if present
          )
        end

        actual_handler_name = handler_name
        if actual_handler_name.nil? && func_params_from_parent.size > 0
          # This part is a bit of a guess; if parse_decorated_function returned a FunctionDefinition,
          # it should have the name. This is a fallback.
          # The `parse_decorated_function` now returns the whole FunctionDefinition, so name is available.
        end


        details = Models::Details.new(file_path: file_path, line: line_num, handler_function: actual_handler_name)
        endpoint = Models::Endpoint.new(
          path: route_path,
          method: http_method,
          description: "", # Robyn doesn't have a standard place for descriptions in routes like FastAPI docstrings
          parameters: api_params,
          request_body: nil, # TODO: Need to figure out how Robyn handles request bodies
          responses: [],     # TODO: Need to figure out how Robyn handles responses
          details: details
        )
        @results << endpoint
      end

      # Extracts path parameters from a route string for Robyn.
      # e.g. "/users/:id/posts/:post_id" -> ["id", "post_id"]
      private def extract_path_params_from_route(route_path : String) : Array(String)
        params = [] of String
        # Robyn uses :param_name syntax for path parameters
        route_path.scan(/:([a-zA-Z_][a-zA-Z0-9_]*)/) do |match|
          params << match[1]
        end
        params.uniq
      end

    end
  end
end
