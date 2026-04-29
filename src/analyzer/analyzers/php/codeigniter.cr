require "../../engines/php_engine"

module Analyzer::Php
  class CodeIgniter < PhpEngine
    # CI4 placeholders → param names. CI3 uses the same shapes.
    PLACEHOLDER_MAP = {
      "any"      => "any",
      "segment"  => "segment",
      "num"      => "num",
      "alpha"    => "alpha",
      "alphanum" => "alphanum",
      "hash"     => "hash",
    }

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint

      return endpoints unless path.ends_with?(".php")

      # CI4: app/Config/Routes.php  |  CI3: application/config/routes.php
      if path.includes?("Config/Routes.php") || path.includes?("application/config/routes.php")
        endpoints.concat(analyze_routes_file(path))
      end

      endpoints
    end

    private def analyze_routes_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      begin
        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          content = file.gets_to_end
          endpoints.concat(analyze_routes_content(content, "", path))
          endpoints.concat(analyze_ci3_routes(content, path))
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

      # 1. Group routes: $routes->group('prefix', [opts]?, function($routes) { ... })
      group_pattern = /\$routes->group\s*\(\s*['"]([^'"]+)['"]\s*(?:,\s*\[(?:[^\[\]]|\[[^\[\]]*\])*\])?\s*,\s*(?:static\s+)?function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?\{((?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*)\}/mi
      working_content.scan(group_pattern).each do |match|
        group_prefix = match[1]
        group_content = match[2]
        new_prefix = build_full_path(prefix, group_prefix)
        endpoints.concat(analyze_routes_content(group_content, new_prefix, file_path))
      end
      working_content = working_content.gsub(group_pattern, "")

      # 2. Environment routes: $routes->environment('env', function($routes) { ... }) — preserve prefix
      env_pattern = /\$routes->environment\s*\(\s*['"][^'"]+['"]\s*,\s*(?:static\s+)?function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?\{((?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*)\}/mi
      working_content.scan(env_pattern).each do |match|
        env_content = match[1]
        endpoints.concat(analyze_routes_content(env_content, prefix, file_path))
      end
      working_content = working_content.gsub(env_pattern, "")

      # 3. HTTP verb routes: $routes->get/post/put/patch/delete/options/head('path', ...)
      verb_pattern = /\$routes->(get|post|put|patch|delete|options|head)\s*\(\s*['"]([^'"]+)['"][^)]*\)/mi
      working_content.scan(verb_pattern).each do |match|
        method = match[1].upcase
        route_path = match[2]
        full_path = build_full_path(prefix, normalize_route(route_path))
        params = extract_ci_path_params(full_path)
        endpoints << Endpoint.new(full_path, method, params, details.dup)
      end

      # 4. $routes->match(['get','post'], 'path', ...)
      match_pattern = /\$routes->match\s*\(\s*\[([^\]]+)\]\s*,\s*['"]([^'"]+)['"][^)]*\)/mi
      working_content.scan(match_pattern).each do |match|
        methods = extract_methods_from_array(match[1])
        route_path = match[2]
        full_path = build_full_path(prefix, normalize_route(route_path))
        params = extract_ci_path_params(full_path)
        methods.each do |http_method|
          endpoints << Endpoint.new(full_path, http_method, params, details.dup)
        end
      end

      # 5. $routes->add('path', ...) — any HTTP verb
      add_pattern = /\$routes->add\s*\(\s*['"]([^'"]+)['"][^)]*\)/mi
      working_content.scan(add_pattern).each do |match|
        route_path = match[1]
        full_path = build_full_path(prefix, normalize_route(route_path))
        params = extract_ci_path_params(full_path)
        ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"].each do |http_method|
          endpoints << Endpoint.new(full_path, http_method, params, details.dup)
        end
      end

      # 6. $routes->resource('photos', ...) — RESTful API resource
      resource_pattern = /\$routes->resource\s*\(\s*['"]([^'"]+)['"][^)]*\)/mi
      working_content.scan(resource_pattern).each do |match|
        resource_name = match[1]
        full_resource_path = build_full_path(prefix, resource_name)
        endpoints.concat(create_resource_endpoints(full_resource_path, file_path))
      end

      # 7. $routes->presenter('photos', ...) — controller-style HTML resource
      presenter_pattern = /\$routes->presenter\s*\(\s*['"]([^'"]+)['"][^)]*\)/mi
      working_content.scan(presenter_pattern).each do |match|
        resource_name = match[1]
        full_resource_path = build_full_path(prefix, resource_name)
        endpoints.concat(create_presenter_endpoints(full_resource_path, file_path))
      end

      endpoints
    end

    # CodeIgniter 3 style: $route['products/(:num)'] = 'catalog/lookup/$1';
    # Optional method qualifier via array: $route['products']['post'] = '...'
    private def analyze_ci3_routes(content : String, file_path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(file_path))

      content.scan(/\$route\s*\[\s*['"]([^'"]+)['"]\s*\](?:\s*\[\s*['"]([^'"]+)['"]\s*\])?\s*=\s*['"]([^'"]+)['"]/mi).each do |match|
        route_path = match[1]
        method_qualifier = match[2]?

        # Skip CI3 reserved config keys
        next if route_path == "default_controller" || route_path == "404_override" ||
                route_path == "translate_uri_dashes"

        method = method_qualifier ? method_qualifier.to_s.upcase : "GET"
        normalized = normalize_route(route_path)
        params = extract_ci_path_params(normalized)
        endpoints << Endpoint.new(normalized, method, params, details.dup)
      end

      endpoints
    end

    # CI4 default RESTful API resource routes
    private def create_resource_endpoints(resource_path : String, file_path : String) : Array(Endpoint)
      details = Details.new(PathInfo.new(file_path))
      base = resource_path.starts_with?("/") ? resource_path : "/#{resource_path}"

      resource_routes = [
        {base, "GET"},                # index
        {"#{base}/new", "GET"},       # new
        {base, "POST"},               # create
        {"#{base}/{id}", "GET"},      # show
        {"#{base}/{id}/edit", "GET"}, # edit
        {"#{base}/{id}", "PUT"},      # update
        {"#{base}/{id}", "PATCH"},    # update
        {"#{base}/{id}", "DELETE"},   # delete
      ]

      resource_routes.map do |route_info|
        path, method = route_info
        params = extract_ci_path_params(path)
        Endpoint.new(path, method, params, details.dup)
      end
    end

    # CI4 presenter (HTML form) resource routes
    private def create_presenter_endpoints(resource_path : String, file_path : String) : Array(Endpoint)
      details = Details.new(PathInfo.new(file_path))
      base = resource_path.starts_with?("/") ? resource_path : "/#{resource_path}"

      presenter_routes = [
        {base, "GET"},                   # index
        {"#{base}/show/{id}", "GET"},    # show
        {"#{base}/new", "GET"},          # new
        {"#{base}/create", "POST"},      # create
        {"#{base}/edit/{id}", "GET"},    # edit
        {"#{base}/update/{id}", "POST"}, # update
        {"#{base}/remove/{id}", "GET"},  # remove
        {"#{base}/delete/{id}", "POST"}, # delete
      ]

      presenter_routes.map do |route_info|
        path, method = route_info
        params = extract_ci_path_params(path)
        Endpoint.new(path, method, params, details.dup)
      end
    end

    # Convert CI placeholders to braces:
    #   /users/(:num)     -> /users/{num}
    #   /files/(:any)     -> /files/{any}
    #   /post/(:segment)  -> /post/{segment}
    private def normalize_route(route_path : String) : String
      normalized = route_path.gsub(/\(:(\w+)\)/) do |_match|
        token = $1
        name = PLACEHOLDER_MAP.fetch(token, token)
        "{#{name}}"
      end
      normalized.starts_with?("/") ? normalized : "/#{normalized}"
    end

    # Extract path params, deduplicating by appending positional suffixes when
    # the same placeholder name appears multiple times (e.g. /a/{any}/b/{any}).
    private def extract_ci_path_params(route_path : String) : Array(Param)
      params = [] of Param
      counts = Hash(String, Int32).new(0)
      route_path.scan(/\{(\w+)\}/) do |match|
        name = match[1]
        counts[name] += 1
        param_name = counts[name] > 1 ? "#{name}#{counts[name]}" : name
        params << Param.new(param_name, "", "path")
      end
      params
    end

    private def extract_methods_from_array(methods_str : String) : Array(String)
      methods = [] of String
      methods_str.scan(/['"]([^'"]+)['"]/) do |match|
        methods << match[1].upcase
      end
      methods
    end
  end
end
