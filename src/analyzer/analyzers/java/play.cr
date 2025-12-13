require "../../../models/analyzer"

module Analyzer::Java
  class Play < Analyzer
    def analyze
      file_list = get_all_files()
      routes_files = [] of String
      
      # First pass: find all routes files
      file_list.each do |path|
        next unless File.exists?(path)
        
        if path.ends_with?("routes") || path.ends_with?("routes.conf") || path.includes?("/conf/routes")
          routes_files << path
        end
      end
      
      # Process each routes file
      routes_files.each do |routes_path|
        process_routes_file(routes_path)
      end

      Fiber.yield
      @result
    end

    # Process a Play routes file
    private def process_routes_file(path : String)
      content = File.read(path)
      lines = content.split('\n')

      lines.each_with_index do |line, index|
        stripped_line = line.strip
        
        # Skip comments and empty lines
        next if stripped_line.empty? || stripped_line.starts_with?("#")
        
        # Match route definitions: METHOD /path controller.action
        # Example: GET /users/:id controllers.Users.show(id: Long)
        if route_match = stripped_line.match(/^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s+([^\s]+)\s+(\S+)/)
          method = route_match[1]
          route_path = route_match[2]
          action = route_match[3]
          
          endpoint = create_endpoint(route_path, method, path, index + 1)
          
          # Extract path parameters
          extract_path_params(endpoint, route_path)
          
          # Extract query parameters from action signature
          extract_params_from_action(endpoint, action)
          
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
          next if param_def.includes?("=") && param_def.match(/=\s*"/)
          
          # Extract parameter name and type
          # Formats: "id: Long", "name: String"
          if param_match = param_def.match(/^(\w+)\s*:\s*\w+/)
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

    # Create an endpoint with the given path and method
    private def create_endpoint(path : String, method : String, source : String, line_number : Int32)
      details = Details.new(PathInfo.new(source, line_number))
      params = [] of Param

      Endpoint.new(path, method, params, details)
    end
  end
end
