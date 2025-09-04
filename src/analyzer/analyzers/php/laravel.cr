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
      begin
        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          content = file.gets_to_end
          endpoints = analyze_routes_content(content, "", path)
        end
      rescue e
        logger.debug "Error analyzing routes file #{path}: #{e}"
      end
      endpoints
    end

    private def analyze_controller_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end

        # Look for Laravel Route attributes on controller methods
        # e.g., #[Route('/users', methods: ['GET'])]
        method_matches = content.scan(/#\[Route\s*\(([^]]*)\]\s*public\s+function\s+(\w+)/m)
        method_matches.each do |match|
          attribute_content = match[1] # This is the content of the attribute

          path_match = attribute_content.match(/['"]([^'"]+)['"]/)
          next unless path_match

          route_path = path_match[1]
          params = extract_route_params(route_path)
          details = Details.new(PathInfo.new(path))

          methods = [] of String
          methods_match = attribute_content.match(/methods:\s*\[([^\]]*)\]/i)
          if methods_match
            methods = extract_methods_from_array(methods_match[1])
          else
            # also check for single method: methods: 'POST' or methods: "POST"
            method_match = attribute_content.match(/methods:\s*['"]([^'"]+)['"]/)
            if method_match
              methods << method_match[1].upcase
            end
          end

          if methods.empty?
            methods << "GET"
          end

          methods.each do |http_method|
            endpoints << Endpoint.new(route_path, http_method, params, details.dup)
          end
        end
      end

      endpoints
    end

    private def analyze_routes_content(content : String, prefix : String, file_path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(file_path))

      # 1. Simple routes: Route::get, Route::post, etc.
      route_patterns = [
        /Route::(get|post|put|patch|delete|options|head)\s*\(\s*['"]([^'"]+)['"][^)]*\)/mi,
        /Route::match\s*\(\s*\[([^\]]+)\]\s*,\s*['"]([^'"]+)['"][^)]*\)/mi,
        /Route::any\s*\(\s*['"]([^'"]+)['"][^)]*\)/mi,
      ]

      route_patterns.each do |pattern|
        matches = content.scan(pattern)
        matches.each do |match|
          full_path = ""
          methods = [] of String

          case pattern
          when route_patterns[0] # Single method
            methods << match[1].upcase
            route_path = match[2]
            full_path = build_full_path(prefix, route_path)
          when route_patterns[1] # Route::match
            methods = extract_methods_from_array(match[1])
            route_path = match[2]
            full_path = build_full_path(prefix, route_path)
          when route_patterns[2] # Route::any
            methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"]
            route_path = match[1]
            full_path = build_full_path(prefix, route_path)
          end

          params = extract_route_params(full_path)
          methods.each do |http_method|
            endpoints << Endpoint.new(full_path, http_method, params, details.dup)
          end
        end
      end

      # 2. Resource routes
      resource_matches = content.scan(/Route::resource\s*\(\s*['"]([^'"]+)['"][^)]*\)/mi)
      resource_matches.each do |match|
        resource_name = match[1]
        full_resource_path = build_full_path(prefix, resource_name)
        endpoints.concat(create_resource_endpoints(full_resource_path.lstrip('/'), file_path))
      end

      api_resource_matches = content.scan(/Route::apiResource\s*\(\s*['"]([^'"]+)['"][^)]*\)/mi)
      api_resource_matches.each do |match|
        resource_name = match[1]
        full_resource_path = build_full_path(prefix, resource_name)
        endpoints.concat(create_api_resource_endpoints(full_resource_path.lstrip('/'), file_path))
      end

      # 3. Group routes (recursive)
      # Route::prefix(...)->group(...)
      fluent_group_matches = content.scan(/Route::prefix\s*\(\s*['"]([^'"]+)['"]\s*\)->group\s*\(\s*function\s*\([^)]*\)\s*\{((?:[^{}]|{[^{}]*})*)\}/mi)
      fluent_group_matches.each do |match|
        group_prefix = match[1]
        group_content = match[2]
        new_prefix = build_full_path(prefix, group_prefix)
        endpoints.concat(analyze_routes_content(group_content, new_prefix, file_path))
      end

      # Route::group with array options
      group_matches = content.scan(/Route::group\s*\(\s*\[(.*?)\]\s*,\s*function\s*\([^)]*\)\s*\{((?:[^{}]|{[^{}]*})*)\}/mi)
      group_matches.each do |match|
        options_str = match[1]
        group_content = match[2]

        new_prefix = prefix
        if prefix_match = options_str.match(/['"]prefix['"]\s*=>\s*['"]([^'"]+)['"]/)
          new_prefix = build_full_path(prefix, prefix_match[1])
        end

        endpoints.concat(analyze_routes_content(group_content, new_prefix, file_path))
      end

      # Simple group with no prefix: Route::group(function() { ... })
      simple_group_matches = content.scan(/Route::group\s*\(\s*function\s*\([^)]*\)\s*\{((?:[^{}]|{[^{}]*})*)\}/mi)
      simple_group_matches.each do |match|
        group_content = match[1]
        endpoints.concat(analyze_routes_content(group_content, prefix, file_path))
      end

      endpoints
    end

    private def build_full_path(prefix : String, path : String) : String
      return prefix if path == "/" && !prefix.empty?
      return path if prefix.empty?

      full_path = "/#{prefix.strip('/')}/#{path.strip('/')}"
      full_path = full_path.gsub(/\/+/, "/")
      full_path = full_path.chomp('/') if full_path.size > 1
      full_path
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
  end
end
