require "../../../models/analyzer"

module Analyzer::Scala
  class Akka < Analyzer
    SCALA_EXTENSION = "scala"
    HTTP_METHODS    = %w[get post put delete patch head options]

    def analyze
      file_list = get_all_files()
      file_list.each do |path|
        next unless File.exists?(path)

        if path.ends_with?(".#{SCALA_EXTENSION}")
          process_scala_file(path)
        end
      end

      Fiber.yield
      @result
    end

    # Process individual Scala files to analyze Akka HTTP routing
    private def process_scala_file(path : String)
      content = File.read(path)
      extract_routes_from_content(path, content)
    end

    # Extract routes from Akka HTTP DSL
    private def extract_routes_from_content(path : String, content : String)
      lines = content.split('\n')
      prefix_stack = [] of String

      lines.each_with_index do |line, index|
        stripped_line = line.strip

        # Handle path prefixes: path("api") { ... } or pathPrefix("api") { ... }
        if path_match = stripped_line.match(/path(?:Prefix)?\s*\(\s*"([^"]+)"\s*\)\s*\{/)
          route_path = path_match[1]
          # Normalize path to start with /
          route_path = "/#{route_path}" unless route_path.starts_with?("/")
          prefix_stack.push(route_path)
          next
        end

        # Check for closing braces to pop from prefix stack
        if stripped_line == "}"
          prefix_stack.pop if !prefix_stack.empty?
          next
        end

        # Handle HTTP method directives: get { complete("response") }
        HTTP_METHODS.each do |method|
          # Pattern 1: get { ... } (no path, uses current prefix)
          if stripped_line =~ /^#{method}\s*\{/
            full_path = prefix_stack.empty? ? "/" : prefix_stack.join("")
            endpoint = create_endpoint(full_path, method.upcase, path)
            extract_parameters_from_context(endpoint, line, content, index)
            @result << endpoint
            next
          end

          # Pattern 2: path("users" / IntNumber) { userId => get { ... } }
          # Pattern 3: path("users") { get { ... } }
          if method_match = stripped_line.match(/path\s*\(\s*"([^"]+)"(?:\s*\/\s*([^)]+))?\s*\)/)
            route_path = method_match[1]
            route_path = "/#{route_path}" unless route_path.starts_with?("/")
            
            # Check if there's a path parameter
            param_matcher = method_match[2]?
            if param_matcher
              # Extract parameter name if present (e.g., IntNumber, Segment, etc.)
              # For now, use a generic {id} pattern
              route_path = "#{route_path}/{id}"
            end

            # Look ahead for the HTTP method on the same or next line
            context_lines = lines[index..(index + 5).clamp(0, lines.size - 1)]
            context = context_lines.join(" ")
            
            HTTP_METHODS.each do |m|
              if context.includes?("#{m} {")
                full_path = prefix_stack.empty? ? route_path : "#{prefix_stack.join("")}#{route_path}"
                endpoint = create_endpoint(full_path, m.upcase, path)
                extract_parameters_from_context(endpoint, context, content, index)
                @result << endpoint
              end
            end
          end

          # Pattern 4: concat(get { ... }, post { ... })
          if stripped_line.includes?("concat(")
            HTTP_METHODS.each do |m|
              if stripped_line.includes?("#{m} {")
                full_path = prefix_stack.empty? ? "/" : prefix_stack.join("")
                endpoint = create_endpoint(full_path, m.upcase, path)
                extract_parameters_from_context(endpoint, line, content, index)
                @result << endpoint
              end
            end
          end
        end
      end
    end

    # Create an endpoint with the given path and method
    private def create_endpoint(path : String, method : String, source : String)
      details = Details.new(PathInfo.new(source, 0))
      params = [] of Param

      # Extract path parameters from the URL
      path_params = extract_path_parameters(path)
      params.concat(path_params)

      Endpoint.new(path, method, params, details)
    end

    # Extract path parameters from URL patterns like {id}
    private def extract_path_parameters(path : String) : Array(Param)
      params = [] of Param

      # Match {param} patterns
      path.scan(/\{([^}]+)\}/) do |match|
        param_name = match[1]
        param = Param.new(param_name, "", "path")
        params << param
      end

      params
    end

    # Extract additional parameters from the route handler
    private def extract_parameters_from_context(endpoint : Endpoint, line : String, content : String, line_index : Int32)
      # Look for common parameter patterns in Akka HTTP handlers
      
      # Check for entity(as[Type]) patterns for request bodies
      if line.includes?("entity(as[") && (type_match = line.match(/entity\(as\[([^\]]+)\]/))
        param_type = type_match[1]
        param = Param.new("body", param_type, "json")
        endpoint.push_param(param)
      end

      # Check for parameter directives
      if line.includes?("parameter(")
        line.scan(/parameter\(['"]([^'"]+)['"]\)/) do |match|
          param_name = match[1]
          param = Param.new(param_name, "", "query")
          endpoint.push_param(param)
        end
      end

      # Check for parameters directive (multiple parameters)
      if line.includes?("parameters(")
        line.scan(/['"]([^'"]+)['"]\.as\[/) do |match|
          param_name = match[1]
          param = Param.new(param_name, "", "query")
          endpoint.push_param(param)
        end
      end

      # Check for headerValueByName patterns
      if line.includes?("headerValueByName(")
        line.scan(/headerValueByName\(['"]([^'"]+)['"]\)/) do |match|
          header_name = match[1]
          param = Param.new(header_name, "", "header")
          endpoint.push_param(param)
        end
      end

      # Check for optionalHeaderValueByName patterns
      if line.includes?("optionalHeaderValueByName(")
        line.scan(/optionalHeaderValueByName\(['"]([^'"]+)['"]\)/) do |match|
          header_name = match[1]
          param = Param.new(header_name, "", "header")
          endpoint.push_param(param)
        end
      end
    end
  end
end
