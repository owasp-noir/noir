require "../../../models/analyzer"
require "../../../utils/utils.cr"

module Analyzer::Php
  class Laravel < Analyzer
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

      # Analyze Laravel routes files
      if path.includes?("routes/") && (path.ends_with?("web.php") || path.ends_with?("api.php"))
        endpoints.concat(analyze_routes_file(path))
      end

      # Analyze Laravel controller files
      if path.includes?("app/Http/Controllers/") && path.ends_with?(".php")
        endpoints.concat(analyze_controller_file(path))
      end

      endpoints
    end

    private def analyze_routes_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end

        # Match Route::method('path', ...)
        route_patterns = [
          # Route::get('/path', [Controller::class, 'method'])
          /Route::(get|post|put|patch|delete|options|head)\s*\(\s*['"]([^'"]+)['"][^)]*\)/mi,
          # Route::match(['GET', 'POST'], '/path', ...)
          /Route::match\s*\(\s*\[([^\]]+)\]\s*,\s*['"]([^'"]+)['"][^)]*\)/mi,
          # Route::any('/path', ...)
          /Route::any\s*\(\s*['"]([^'"]+)['"][^)]*\)/mi,
        ]

        route_patterns.each do |pattern|
          matches = content.scan(pattern)
          matches.each do |match|
            case pattern
            when route_patterns[0] # Single method routes
              method = match[1].upcase
              route_path = match[2]
              params = extract_route_params(route_path)
              details = Details.new(PathInfo.new(path))
              endpoints << Endpoint.new(route_path, method, params, details)
            when route_patterns[1] # Route::match with multiple methods
              methods_str = match[1]
              route_path = match[2]
              methods = extract_methods_from_array(methods_str)
              params = extract_route_params(route_path)
              details = Details.new(PathInfo.new(path))

              methods.each do |http_method|
                endpoints << Endpoint.new(route_path, http_method, params, details)
              end
            when route_patterns[2] # Route::any
              route_path = match[1]
              all_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"]
              params = extract_route_params(route_path)
              details = Details.new(PathInfo.new(path))

              all_methods.each do |http_method|
                endpoints << Endpoint.new(route_path, http_method, params, details)
              end
            end
          end
        end

        # Match Route::resource('resource', Controller::class)
        resource_matches = content.scan(/Route::resource\s*\(\s*['"]([^'"]+)['"][^)]*\)/mi)
        resource_matches.each do |match|
          resource_name = match[1]
          endpoints.concat(create_resource_endpoints(resource_name, path))
        end

        # Match Route::apiResource('resource', Controller::class)
        api_resource_matches = content.scan(/Route::apiResource\s*\(\s*['"]([^'"]+)['"][^)]*\)/mi)
        api_resource_matches.each do |match|
          resource_name = match[1]
          endpoints.concat(create_api_resource_endpoints(resource_name, path))
        end

        # Match Route::group with prefix - improved regex
        group_matches = content.scan(/Route::group\s*\(\s*\[[^}]*['"]prefix['"]\s*=>\s*['"]([^'"]+)['"][^}]*\]\s*,\s*function\s*\([^)]*\)\s*\{((?:[^{}]|{[^{}]*})*)\}/mi)
        group_matches.each do |match|
          prefix = match[1]
          group_content = match[2]
          group_endpoints = analyze_routes_content(group_content, prefix, path)
          endpoints.concat(group_endpoints)
        end

        # Also look for simple Route::group without prefix for completeness
        simple_group_matches = content.scan(/Route::group\s*\(\s*function\s*\([^)]*\)\s*\{((?:[^{}]|{[^{}]*})*)\}/mi)
        simple_group_matches.each do |match|
          group_content = match[1]
          group_endpoints = analyze_routes_content(group_content, "", path)
          endpoints.concat(group_endpoints)
        end
      end

      endpoints
    end

    private def analyze_controller_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end

        # Look for Laravel Route attributes on controller methods
        method_matches = content.scan(/#\[Route\s*\(\s*['"]([^'"]+)['"][^)]*\)\]\s*public\s+function\s+(\w+)/m)
        method_matches.each do |match|
          route_path = match[1]

          # Default to GET if no specific method found
          http_method = extract_http_method_from_path_context(content, match[0])
          params = extract_route_params(route_path)
          details = Details.new(PathInfo.new(path))

          endpoints << Endpoint.new(route_path, http_method, params, details)
        end
      end

      endpoints
    end

    private def analyze_routes_content(content : String, prefix : String, file_path : String) : Array(Endpoint)
      endpoints = [] of Endpoint

      # Simple parsing for route definitions within groups
      route_matches = content.scan(/Route::(get|post|put|patch|delete|options|head)\s*\(\s*['"]([^'"]+)['"][^)]*\)/mi)
      route_matches.each do |match|
        method = match[1].upcase
        route_path = match[2]

        # Build full path with prefix
        if prefix.empty?
          full_path = route_path
        else
          full_path = "/#{prefix.strip('/')}/#{route_path.strip('/')}"
          full_path = full_path.gsub(/\/+/, "/")               # Remove duplicate slashes
          full_path = full_path.chomp("/") if full_path != "/" # Remove trailing slash unless it's root
        end

        params = extract_route_params(full_path)
        details = Details.new(PathInfo.new(file_path))
        endpoints << Endpoint.new(full_path, method, params, details)
      end

      # Also check for Route::match within groups
      match_routes = content.scan(/Route::match\s*\(\s*\[([^\]]+)\]\s*,\s*['"]([^'"]+)['"][^)]*\)/mi)
      match_routes.each do |match|
        methods_str = match[1]
        route_path = match[2]
        methods = extract_methods_from_array(methods_str)

        # Build full path with prefix
        if prefix.empty?
          full_path = route_path
        else
          full_path = "/#{prefix.strip('/')}/#{route_path.strip('/')}"
          full_path = full_path.gsub(/\/+/, "/")               # Remove duplicate slashes
          full_path = full_path.chomp("/") if full_path != "/" # Remove trailing slash unless it's root
        end

        params = extract_route_params(full_path)
        details = Details.new(PathInfo.new(file_path))

        methods.each do |method|
          endpoints << Endpoint.new(full_path, method, params, details)
        end
      end

      endpoints
    end

    private def create_resource_endpoints(resource : String, file_path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(file_path))

      # Standard Laravel resource routes
      resource_routes = [
        {"/#{resource}", "GET"},           # index
        {"/#{resource}/create", "GET"},    # create
        {"/#{resource}", "POST"},          # store
        {"/#{resource}/{id}", "GET"},      # show
        {"/#{resource}/{id}/edit", "GET"}, # edit
        {"/#{resource}/{id}", "PUT"},      # update
        {"/#{resource}/{id}", "PATCH"},    # update
        {"/#{resource}/{id}", "DELETE"},   # destroy
      ]

      resource_routes.each do |route_info|
        path, method = route_info
        params = extract_route_params(path)
        endpoints << Endpoint.new(path, method, params, details)
      end

      endpoints
    end

    private def create_api_resource_endpoints(resource : String, file_path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(file_path))

      # API resource routes (excludes create and edit forms)
      api_resource_routes = [
        {"/#{resource}", "GET"},         # index
        {"/#{resource}", "POST"},        # store
        {"/#{resource}/{id}", "GET"},    # show
        {"/#{resource}/{id}", "PUT"},    # update
        {"/#{resource}/{id}", "PATCH"},  # update
        {"/#{resource}/{id}", "DELETE"}, # destroy
      ]

      api_resource_routes.each do |route_info|
        path, method = route_info
        params = extract_route_params(path)
        endpoints << Endpoint.new(path, method, params, details)
      end

      endpoints
    end

    private def extract_methods_from_array(methods_str : String) : Array(String)
      methods = [] of String
      method_matches = methods_str.scan(/['"]([^'"]+)['"]/)
      method_matches.each do |match|
        methods << match[1].upcase
      end
      methods
    end

    private def extract_route_params(route_path : String) : Array(Param)
      params = [] of Param

      # Extract Laravel route parameters like {id}, {slug}, etc.
      param_matches = route_path.scan(/\{(\w+)\}/)
      param_matches.each do |match|
        param_name = match[1]
        params << Param.new(param_name, "", "path")
      end

      # Extract optional parameters like {id?}
      optional_matches = route_path.scan(/\{(\w+)\?\}/)
      optional_matches.each do |match|
        param_name = match[1]
        params << Param.new(param_name, "", "path")
      end

      params
    end

    private def extract_http_method_from_path_context(content : String, route_match : String) : String
      # Try to find the HTTP method from the Route attribute context
      route_start = content.index(route_match)
      if route_start
        context_start = [route_start - 100, 0].max
        context_end = [route_start + 200, content.size].min
        context = content[context_start..context_end]

        # Look for methods: ['GET'] or methods: 'POST'
        if match = context.match(/methods?\s*[:=]\s*['"]?([^'",\]]+)['"]?/)
          return match[1].upcase
        end
      end

      "GET" # Default to GET if no method specified
    end
  end
end
