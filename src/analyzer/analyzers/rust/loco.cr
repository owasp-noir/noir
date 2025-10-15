require "../../../models/analyzer"

module Analyzer::Rust
  class Loco < Analyzer
    def analyze
      # Source Analysis for Loco framework routes
      # Loco follows Rails conventions with controllers and actions
      # Loco uses Axum under the hood, so we extract parameters using Axum patterns

      # Simple pattern to match function definitions
      pattern = /pub\s+async\s+fn\s+(\w+)/

      channel = Channel(String).new

      begin
        populate_channel_with_files(channel)

        WaitGroup.wait do |wg|
          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)

                  if File.exists?(path) && File.extname(path) == ".rs"
                    lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)
                    lines.each_with_index do |line, index|
                      if line.to_s.includes? "pub async fn"
                        match = line.match(pattern)
                        if match
                          begin
                            method_name = match[1]
                            # Convert Rails-style action names to route paths
                            endpoint_path = action_to_path(method_name, path)
                            details = Details.new(PathInfo.new(path, index + 1))
                            # Infer HTTP method from action name and context
                            http_method = infer_http_method(method_name, line)
                            
                            endpoint = Endpoint.new(endpoint_path, http_method, details)
                            
                            # Extract path parameters from the endpoint path
                            extract_path_params(endpoint_path, endpoint)
                            
                            # Extract parameters from function signature and body
                            extract_function_params(lines, index, endpoint)
                            
                            result << endpoint
                          rescue e
                            # Log the exception for debugging
                            logger.debug "Error parsing Loco endpoint: #{e.message}"
                          end
                        end
                      end
                    end
                  end
                rescue e : File::NotFoundError
                  logger.debug "File not found: #{path}"
                rescue e
                  logger.debug "Error in Loco analyzer: #{e.message}"
                end
              end
            end
          end
        end
      rescue e
        logger.debug "Error in Loco analyzer setup: #{e.message}"
      end

      result
    end

    private def action_to_path(action_name : String, file_path : String) : String
      # Extract controller name from file path if possible
      controller = ""
      if file_path.includes?("/controllers/") || file_path.includes?("/controller/")
        path_parts = file_path.split("/")
        controller_file = path_parts.last.gsub(/\.rs$/, "")
        controller = controller_file.gsub(/_controller$/, "")
      end

      # Convert Rails-style action names to RESTful paths
      case action_name
      when "index"
        controller.empty? ? "/" : "/#{controller}"
      when "show"
        controller.empty? ? "/:id" : "/#{controller}/:id"
      when "new"
        controller.empty? ? "/new" : "/#{controller}/new"
      when "create"
        controller.empty? ? "/" : "/#{controller}"
      when "edit"
        controller.empty? ? "/:id/edit" : "/#{controller}/:id/edit"
      when "update"
        controller.empty? ? "/:id" : "/#{controller}/:id"
      when "destroy", "delete"
        controller.empty? ? "/:id" : "/#{controller}/:id"
      else
        # For custom actions, create a path based on action name
        base_path = controller.empty? ? "" : "/#{controller}"
        "#{base_path}/#{action_name.gsub(/([A-Z])/, "_\\1").downcase.lstrip("_")}"
      end
    end

    private def infer_http_method(action_name : String, line : String) : String
      # Infer HTTP method from Rails conventions and line context
      case action_name
      when "index", "show", "new", "edit"
        "GET"
      when "create", "login", "signup", "register"
        "POST"
      when "update"
        if line.includes?("PUT") || line.includes?("put")
          "PUT"
        else
          "PATCH"
        end
      when "destroy", "delete"
        "DELETE"
      else
        # Check line for HTTP method hints
        if line.includes?("post") || line.includes?("POST")
          "POST"
        elsif line.includes?("put") || line.includes?("PUT")
          "PUT"
        elsif line.includes?("delete") || line.includes?("DELETE")
          "DELETE"
        elsif line.includes?("patch") || line.includes?("PATCH")
          "PATCH"
        # Check if Form<T> is present, which typically indicates POST
        elsif line.includes?("Form<")
          "POST"
        else
          "GET"
        end
      end
    end

    # Extract path parameters from the route pattern like /:id
    private def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/:(\w+)/) do |match|
        param_name = match[1]
        endpoint.push_param(Param.new(param_name, "", "path"))
      end
    end

    # Extract parameters from function signature and body
    # Loco uses Axum extractors, so we look for patterns like:
    # - Path<T> for path parameters
    # - Query<T> for query parameters
    # - Json<T> for JSON body
    # - Form<T> for form data
    # - HeaderMap or headers for header access
    private def extract_function_params(lines : Array(String), start_index : Int32, endpoint : Endpoint)
      # Look ahead up to 30 lines for the function definition and body
      in_function = false
      brace_count = 0
      seen_opening_brace = false
      function_signature = ""

      (start_index...[start_index + 30, lines.size].min).each do |i|
        line = lines[i]

        # Build the function signature (can span multiple lines)
        if !seen_opening_brace
          function_signature += " " + line.strip
        end

        # Track if we're inside the function
        if line.includes?("async fn ") || line.includes?("fn ")
          in_function = true
        end

        # Track braces to know when function ends
        brace_count += line.count('{')
        if brace_count > 0
          seen_opening_brace = true
        end
        brace_count -= line.count('}')

        # Stop if we've moved past the function
        if in_function && seen_opening_brace && brace_count == 0 && i > start_index
          break
        end

        # Also stop if we hit another function
        if i > start_index && line.strip.starts_with?("pub async fn") || line.strip.starts_with?("async fn")
          break
        end
      end

      # Extract the parameter section (between parentheses, before ->)
      # Split signature at -> to separate parameters from return type
      param_section = function_signature.split("->").first? || function_signature
      
      # Now extract parameters from the parameter section only
      
      # Extract Query parameters - Query<T> in function parameters
      if param_section.includes?("Query<")
        endpoint.push_param(Param.new("query", "", "query"))
      end

      # Extract Path parameters from Path<T> in function parameters
      # Note: We already extracted path params from the route, but this handles explicit Path<T> extractors
      if param_section.includes?("Path<")
        # The path params are already extracted from the route pattern, so we don't need to add duplicates
        # Just verify they're there
      end

      # Extract JSON body from Json<T> in parameters (not return type)
      if param_section.includes?("Json<")
        endpoint.push_param(Param.new("body", "", "json"))
      end

      # Extract form body from Form<T> in parameters (not return type)
      if param_section.includes?("Form<")
        endpoint.push_param(Param.new("form", "", "form"))
      end

      # Extract headers - look for HeaderMap or headers parameter
      if param_section.includes?("HeaderMap") || param_section.includes?(": HeaderMap")
        # Look in the function body for specific header usage
        (start_index...[start_index + 30, lines.size].min).each do |i|
          line = lines[i]
          
          # Extract specific header names from .get("header_name") or headers.get("header_name")
          if line.includes?(".get(\"")
            line.scan(/\.get\("([^"]+)"\)/) do |match|
              header_name = match[1]
              # Only add if it looks like a header name (contains dashes or is common header)
              if header_name.includes?("-") || ["Authorization", "Content-Type", "Accept"].includes?(header_name)
                endpoint.push_param(Param.new(header_name, "", "header"))
              end
            end
          end
        end
      end

      # Extract cookies from cookie access patterns
      (start_index...[start_index + 30, lines.size].min).each do |i|
        line = lines[i]
        
        # Look for .cookie("name") patterns
        if line.includes?(".cookie(\"")
          line.scan(/\.cookie\("([^"]+)"\)/) do |match|
            cookie_name = match[1]
            endpoint.push_param(Param.new(cookie_name, "", "cookie"))
          end
        end
      end
    end
  end
end
