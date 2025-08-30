require "../../../models/analyzer"
require "../../../utils/utils.cr"

module Analyzer::Php
  class Symfony < Analyzer
    def analyze
      result = [] of Endpoint
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

                  if File.exists?(path)
                    result.concat(analyze_file(path))
                  end
                rescue e : File::NotFoundError
                  logger.debug "File not found: #{path}"
                rescue e
                  logger.debug "Error analyzing #{path}: #{e}"
                end
              end
            end
          end
        end
      rescue e
        logger.debug e
      end

      Fiber.yield
      result
    end

    private def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      
      # Analyze PHP controller files
      if path.ends_with?(".php")
        endpoints.concat(analyze_php_routes(path))
      end
      
      # Analyze YAML route files
      if path.ends_with?(".yaml") || path.ends_with?(".yml")
        if path.includes?("config") && (path.includes?("routes") || path.includes?("routing"))
          endpoints.concat(analyze_yaml_routes(path))
        end
      end

      endpoints
    end

    private def analyze_php_routes(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      relative_path = get_relative_path(base_path, path)
      
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end
        
        # Look for route annotations (@Route) - more flexible pattern
        annotation_matches = content.scan(/@Route\s*\(\s*["']([^"']+)["']/m)
        annotation_matches.each do |match|
          route_path = match[1]
          
          # Look for methods in the annotation context
          # Find the full annotation block
          route_start = content.index(match[0])
          if route_start
            # Get a reasonable context around the annotation
            context_start = [route_start - 200, 0].max
            context_end = [route_start + 300, content.size].min
            context = content[context_start..context_end]
            
            methods = extract_methods_from_annotation_context(context)
            methods = ["GET"] if methods.empty?
            
            params = extract_route_params(route_path)
            details = Details.new(PathInfo.new(path))
            
            methods.each do |method|
              endpoints << Endpoint.new(route_path, method.upcase, params, details)
            end
          end
        end
        
        # Look for route attributes (#[Route]) - PHP 8 style
        attribute_matches = content.scan(/#\[Route\s*\(\s*['"]([^'"]+)['"][^)]*\)/m)
        attribute_matches.each do |match|
          route_path = match[1]
          
          # Look for methods in the attribute context
          route_start = content.index(match[0])
          if route_start
            context_start = [route_start - 50, 0].max
            context_end = [route_start + 200, content.size].min
            context = content[context_start..context_end]
            
            methods = extract_methods_from_attribute_context(context)
            methods = ["GET"] if methods.empty?
            
            params = extract_route_params(route_path)
            details = Details.new(PathInfo.new(path))
            
            methods.each do |method|
              endpoints << Endpoint.new(route_path, method.upcase, params, details)
            end
          end
        end
      end
      
      endpoints
    end

    private def extract_methods_from_annotation_context(context : String) : Array(String)
      methods = [] of String
      
      # Look for methods={"GET","POST"} or methods={"GET"}
      if match = context.match(/methods\s*=\s*\{([^}]+)\}/)
        methods_str = match[1]
        method_matches = methods_str.scan(/["']([^"']+)["']/)
        method_matches.each do |method_match|
          methods << method_match[1]
        end
      end
      
      methods
    end

    private def extract_methods_from_attribute_context(context : String) : Array(String)
      methods = [] of String
      
      # Look for methods: ['GET', 'POST'] or methods: ['GET']
      if match = context.match(/methods\s*:\s*\[([^\]]+)\]/)
        methods_str = match[1]
        method_matches = methods_str.scan(/['"]([^'"]+)['"]/)
        method_matches.each do |method_match|
          methods << method_match[1]
        end
      end
      
      methods
    end

    private def analyze_yaml_routes(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      
      begin
        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          content = file.gets_to_end
          
          # Simple YAML route parsing for Symfony
          # Look for patterns like:
          # route_name:
          #   path: /api/users/{id}
          #   methods: [GET, POST]
          
          route_matches = content.scan(/^\s*\w+:\s*\n\s*path:\s*["']?([^"'\n]+)["']?(?:\n\s*methods:\s*\[([^\]]+)\])?/m)
          route_matches.each do |match|
            route_path = match[1]
            methods_str = match[2]?
            
            if methods_str
              methods = methods_str.split(",").map(&.strip.gsub(/["'\[\]]/, ""))
            else
              methods = ["GET"]
            end
            
            params = extract_route_params(route_path)
            details = Details.new(PathInfo.new(path))
            
            methods.each do |method|
              endpoints << Endpoint.new(route_path, method.upcase, params, details)
            end
          end
        end
      rescue e
        logger.debug "Error parsing YAML routes in #{path}: #{e}"
      end
      
      endpoints
    end

    private def extract_route_params(route_path : String) : Array(Param)
      params = [] of Param
      
      # Extract path parameters like {id}, {slug}, etc.
      param_matches = route_path.scan(/\{(\w+)\}/)
      param_matches.each do |match|
        param_name = match[1]
        params << Param.new(param_name, "", "path")
      end
      
      params
    end
  end
end