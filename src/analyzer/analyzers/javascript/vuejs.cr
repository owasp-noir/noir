require "../../../models/analyzer"

module Analyzer::Javascript
  class Vuejs < Analyzer
    def analyze
      channel = Channel(String).new
      result = [] of Endpoint

      begin
        populate_channel_with_files(channel)

        WaitGroup.wait do |wg|
          worker_count = @options["concurrency"].to_s.to_i
          worker_count = 16 if worker_count > 16
          worker_count = 1 if worker_count < 1
          worker_count.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)
                  # Process .js, .ts, .mjs, and .vue files
                  next unless [".js", ".ts", ".mjs", ".vue"].any? { |ext| path.ends_with?(ext) }

                  if File.exists?(path)
                    content = File.read(path, encoding: "utf-8", invalid: :skip)
                    analyze_vue_router_file(path, content, result)
                  end
                rescue e : File::NotFoundError
                  logger.debug "File not found: #{path}"
                rescue e : Exception
                  logger.debug "Error processing file #{path}: #{e.message}"
                end
              end
            end
          end
        end
      rescue e
        logger.debug "Error in Vue.js analyzer: #{e.message}"
      end

      result
    end

    private def analyze_vue_router_file(path : String, content : String, result : Array(Endpoint))
      # Extract routes from Vue Router configurations
      # Handles both Vue 2 and Vue 3 patterns
      
      # Pattern 1: routes: [ ... ] array
      extract_routes_from_array(content, path, result)
      
      # Pattern 2: Individual route objects with router.addRoute or router.push
      extract_individual_routes(content, path, result)
    end

    private def extract_routes_from_array(content : String, file_path : String, result : Array(Endpoint))
      # Find routes array definition
      # Pattern: routes: [ { path: '/path', ... }, ... ]
      # or const routes = [ { path: '/path', ... }, ... ]
      
      # More flexible regex that handles various bracket placements
      routes_match = content.match(/(?:routes\s*:\s*\[|const\s+routes\s*=\s*\[)(.*?)(?:\])/m)
      return unless routes_match && routes_match.size > 1
      
      routes_content = routes_match[1]
      
      # Extract individual route objects
      # Match route objects: { path: '...', ... }
      routes_content.scan(/\{\s*path\s*:\s*['"`]([^'"`]+)['"`]([^}]*)\}/m) do |match|
        next unless match.size > 1
        
        route_path = match[1]
        route_config = match[2]
        
        # Determine HTTP methods from route configuration
        methods = extract_methods_from_route(route_config)
        
        # Create endpoints for each method
        methods.each do |method|
          endpoint = create_endpoint(route_path, method, file_path)
          
          # Extract path parameters
          extract_path_params(route_path, endpoint)
          
          # Extract query parameters from component definitions
          extract_query_params_from_config(route_config, endpoint)
          
          # Add endpoint if not duplicate
          unless result.any? { |e| e.url == endpoint.url && e.method == endpoint.method }
            result << endpoint
          end
        end
      end
    end

    private def extract_individual_routes(content : String, file_path : String, result : Array(Endpoint))
      # Extract individual route registrations
      # Pattern: router.addRoute({ path: '/path', ... })
      # Pattern: router.push('/path')
      
      # addRoute pattern
      content.scan(/router\.addRoute\s*\(\s*\{\s*path\s*:\s*['"`]([^'"`]+)['"`]([^}]*)\}/m) do |match|
        next unless match.size > 1
        
        route_path = match[1]
        route_config = match[2]
        
        methods = extract_methods_from_route(route_config)
        methods.each do |method|
          endpoint = create_endpoint(route_path, method, file_path)
          extract_path_params(route_path, endpoint)
          
          unless result.any? { |e| e.url == endpoint.url && e.method == endpoint.method }
            result << endpoint
          end
        end
      end
    end

    private def extract_methods_from_route(route_config : String) : Array(String)
      # Vue Router doesn't directly specify HTTP methods in route config
      # By default, routes are accessible via GET for navigation
      # However, components may make API calls with different methods
      
      # Check if there are explicit method specifications (custom pattern)
      methods_match = route_config.match(/methods?\s*:\s*\[([^\]]+)\]/)
      if methods_match && methods_match.size > 1
        methods_str = methods_match[1]
        methods = methods_str.scan(/['"`](\w+)['"`]/).map { |m| m[1].upcase }
        return methods if methods.size > 0
      end
      
      # Default to GET for route navigation
      ["GET"]
    end

    private def extract_path_params(route_path : String, endpoint : Endpoint)
      # Extract path parameters from Vue Router dynamic segments
      # Pattern: /users/:id or /users/:id(\\d+) or /posts/:postId
      
      route_path.scan(/:(\w+)(?:\([^)]+\))?/) do |match|
        if match.size > 0
          param_name = match[1]
          unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
            endpoint.push_param(Param.new(param_name, "", "path"))
          end
        end
      end
    end

    private def extract_query_params_from_config(route_config : String, endpoint : Endpoint)
      # Try to extract query parameter hints from route configuration
      # Pattern: query: ['param1', 'param2'] or props: route => ({ query: route.query.param })
      
      # Direct query array definition
      query_match = route_config.match(/query\s*:\s*\[([^\]]+)\]/)
      if query_match && query_match.size > 1
        query_str = query_match[1]
        query_str.scan(/['"`](\w+)['"`]/) do |match|
          if match.size > 0
            param_name = match[1]
            endpoint.push_param(Param.new(param_name, "", "query"))
          end
        end
      end
      
      # Props that reference route.query
      route_config.scan(/route\.query\.(\w+)/) do |match|
        if match.size > 0
          param_name = match[1]
          endpoint.push_param(Param.new(param_name, "", "query"))
        end
      end
      
      # $route.query references (common in component code)
      route_config.scan(/\$route\.query\.(\w+)/) do |match|
        if match.size > 0
          param_name = match[1]
          endpoint.push_param(Param.new(param_name, "", "query"))
        end
      end
    end

    private def create_endpoint(path : String, method : String, file_path : String) : Endpoint
      # Ensure path starts with /
      path = "/#{path}" unless path.starts_with?("/")
      
      endpoint = Endpoint.new(path, method)
      details = Details.new(PathInfo.new(file_path, 1))
      endpoint.details = details
      endpoint
    end
  end
end
