require "../../engines/php_engine"

module Analyzer::Php
  class CakePHP < PhpEngine
    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint

      # Analyze CakePHP routes file
      if path.includes?("config/routes.php")
        endpoints.concat(analyze_routes_file(path))
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

    private def analyze_routes_content(content : String, prefix : String, file_path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(file_path))

      working_content = content

      # 1. Scoped routes
      scope_patterns = [
        /(\$routes|\$builder)->scope\s*\(\s*['"]([^'"]+)['"]\s*,[^,]*,\s*function\s*\(\s*(?:[^$)]+\s+)?\$[^)]+\)\s*\{((?:[^{}]|{[^{}]*})*)\}/mi,
        /(\$routes|\$builder)->scope\s*\(\s*['"]([^'"]+)['"]\s*,\s*function\s*\(\s*(?:[^$)]+\s+)?\$[^)]+\)\s*\{((?:[^{}]|{[^{}]*})*)\}/mi,
      ]

      scope_patterns.each do |pattern|
        working_content.scan(pattern).each do |match|
          # match[1] is variable
          # match[2] is path
          # match[3] is content
          if match.size >= 4
            new_prefix = build_full_path(prefix, match[2])
            endpoints.concat(analyze_routes_content(match[3], new_prefix, file_path))
          end
        end
        working_content = working_content.gsub(pattern, "")
      end

      # 2. Connect routes
      connect_pattern = /(\$routes|\$builder)->connect\s*\(\s*['"]([^'"]+)['"](?:.*?)\[(.*?)\]/mi
      working_content.scan(connect_pattern).each do |match|
        route_path = match[2]
        options_str = match[3]

        full_path = build_full_path(prefix, route_path)
        params = extract_route_params(full_path)

        method = "GET"
        if method_match = options_str.match(/['"]_method['"]\s*=>\s*['"]([^'"]+)['"]/)
          method = method_match[1].upcase
        end

        endpoints << Endpoint.new(full_path, method, params, details.dup)
      end

      # 3. HTTP Verb methods
      verb_patterns = {
        "GET"     => /(\$routes|\$builder)->get\s*\(\s*['"]([^'"]+)['"]/mi,
        "POST"    => /(\$routes|\$builder)->post\s*\(\s*['"]([^'"]+)['"]/mi,
        "PUT"     => /(\$routes|\$builder)->put\s*\(\s*['"]([^'"]+)['"]/mi,
        "PATCH"   => /(\$routes|\$builder)->patch\s*\(\s*['"]([^'"]+)['"]/mi,
        "DELETE"  => /(\$routes|\$builder)->delete\s*\(\s*['"]([^'"]+)['"]/mi,
        "OPTIONS" => /(\$routes|\$builder)->options\s*\(\s*['"]([^'"]+)['"]/mi,
        "HEAD"    => /(\$routes|\$builder)->head\s*\(\s*['"]([^'"]+)['"]/mi,
      }

      verb_patterns.each do |method, pattern|
        working_content.scan(pattern).each do |match|
          route_path = match[2]
          full_path = build_full_path(prefix, route_path)
          params = extract_route_params(full_path)
          endpoints << Endpoint.new(full_path, method, params, details.dup)
        end
      end

      # 4. Resources
      resource_pattern = /(\$routes|\$builder)->resources\s*\(\s*['"]([^'"]+)['"]/mi
      working_content.scan(resource_pattern).each do |match|
        resource_name = match[2]
        full_resource_path = build_full_path(prefix, resource_name)
        endpoints.concat(create_resource_endpoints(full_resource_path, file_path))
      end

      endpoints
    end

    # CakePHP supports both `{id}` and `:id` route params; the latter is not
    # covered by the engine helper.
    private def extract_route_params(route_path : String) : Array(Param)
      params = extract_brace_path_params(route_path)
      route_path.scan(/:(\w+)/).each do |match|
        params << Param.new(match[1], "", "path")
      end
      params
    end

    private def create_resource_endpoints(resource_path : String, file_path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(file_path))

      # Standard REST resource routes
      resource_routes = [
        {resource_path, "GET"},              # index
        {resource_path, "POST"},             # add
        {"#{resource_path}/{id}", "GET"},    # view
        {"#{resource_path}/{id}", "PUT"},    # edit
        {"#{resource_path}/{id}", "PATCH"},  # edit
        {"#{resource_path}/{id}", "DELETE"}, # delete
      ]

      resource_routes.each do |route_info|
        path, method = route_info
        params = extract_route_params(path)
        endpoints << Endpoint.new(path, method, params, details)
      end

      endpoints
    end
  end
end
