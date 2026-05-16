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
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      begin
        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          content = file.gets_to_end
          endpoints = analyze_routes_content(content, "", path, include_callee)
        end
      rescue e
        logger.debug "Error analyzing routes file #{path}: #{e}"
      end
      endpoints
    end

    private def analyze_routes_content(content : String,
                                       prefix : String,
                                       file_path : String,
                                       include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(file_path))

      working_content = content

      # 1. Scoped routes
      scope_patterns = [
        /(\$routes|\$builder)->scope\s*\(\s*['"]([^'"]+)['"]\s*,[^,]*,\s*(?:static\s+)?function\s*\(\s*(?:[^$)]+\s+)?\$[^)]+\)\s*\{((?:[^{}]|{[^{}]*})*)\}/mi,
        /(\$routes|\$builder)->scope\s*\(\s*['"]([^'"]+)['"]\s*,\s*(?:static\s+)?function\s*\(\s*(?:[^$)]+\s+)?\$[^)]+\)\s*\{((?:[^{}]|{[^{}]*})*)\}/mi,
      ]

      scope_patterns.each do |pattern|
        working_content.scan(pattern).each do |match|
          # match[1] is variable
          # match[2] is path
          # match[3] is content
          if match.size >= 4
            new_prefix = build_full_path(prefix, match[2])
            endpoints.concat(analyze_routes_content(match[3], new_prefix, file_path, include_callee))
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
        target = extract_controller_action_target(options_str)

        method = "GET"
        if method_match = options_str.match(/['"]_method['"]\s*=>\s*['"]([^'"]+)['"]/)
          method = method_match[1].upcase
        end

        endpoint = Endpoint.new(full_path, method, params, details.dup)
        attach_route_target_callees(endpoint, target, file_path) if include_callee
        endpoints << endpoint
      end

      # 3. HTTP Verb methods
      verb_patterns = {
        "GET"     => /(\$routes|\$builder)->get\s*\(\s*['"]([^'"]+)['"](?:\s*,\s*\[(.*?)\])?/mi,
        "POST"    => /(\$routes|\$builder)->post\s*\(\s*['"]([^'"]+)['"](?:\s*,\s*\[(.*?)\])?/mi,
        "PUT"     => /(\$routes|\$builder)->put\s*\(\s*['"]([^'"]+)['"](?:\s*,\s*\[(.*?)\])?/mi,
        "PATCH"   => /(\$routes|\$builder)->patch\s*\(\s*['"]([^'"]+)['"](?:\s*,\s*\[(.*?)\])?/mi,
        "DELETE"  => /(\$routes|\$builder)->delete\s*\(\s*['"]([^'"]+)['"](?:\s*,\s*\[(.*?)\])?/mi,
        "OPTIONS" => /(\$routes|\$builder)->options\s*\(\s*['"]([^'"]+)['"](?:\s*,\s*\[(.*?)\])?/mi,
        "HEAD"    => /(\$routes|\$builder)->head\s*\(\s*['"]([^'"]+)['"](?:\s*,\s*\[(.*?)\])?/mi,
      }

      verb_patterns.each do |method, pattern|
        working_content.scan(pattern).each do |match|
          route_path = match[2]
          full_path = build_full_path(prefix, route_path)
          params = extract_route_params(full_path)
          target = extract_controller_action_target(match[3]?)
          endpoint = Endpoint.new(full_path, method, params, details.dup)
          attach_route_target_callees(endpoint, target, file_path) if include_callee
          endpoints << endpoint
        end
      end

      # 4. Resources
      resource_pattern = /(\$routes|\$builder)->resources\s*\(\s*['"]([^'"]+)['"]/mi
      working_content.scan(resource_pattern).each do |match|
        resource_name = match[2]
        full_resource_path = build_full_path(prefix, resource_name)
        endpoints.concat(create_resource_endpoints(full_resource_path, file_path, include_callee, resource_name))
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

    private def create_resource_endpoints(resource_path : String,
                                          file_path : String,
                                          include_callee : Bool,
                                          controller_name : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(file_path))

      # Standard REST resource routes
      resource_routes = [
        {resource_path, "GET", "index"},
        {resource_path, "POST", "add"},
        {"#{resource_path}/{id}", "GET", "view"},
        {"#{resource_path}/{id}", "PUT", "edit"},
        {"#{resource_path}/{id}", "PATCH", "edit"},
        {"#{resource_path}/{id}", "DELETE", "delete"},
      ]

      resource_routes.each do |route_info|
        path, method, action = route_info
        params = extract_route_params(path)
        endpoint = Endpoint.new(path, method, params, details.dup)
        attach_route_target_callees(endpoint, {controller_name, action}, file_path) if include_callee
        endpoints << endpoint
      end

      endpoints
    end

    private def attach_route_target_callees(endpoint : Endpoint,
                                            target : Tuple(String, String)?,
                                            routes_file_path : String)
      return unless target

      method_body = extract_controller_action_body(routes_file_path, target[0], target[1])
      return unless method_body

      body, controller_path, start_line = method_body
      callees = Noir::PhpCalleeExtractor.callees_for_body(body, controller_path, start_line)
      attach_php_callees(endpoint, callees)
    end

    private def extract_controller_action_body(routes_file_path : String,
                                               controller_name : String,
                                               action_name : String) : Tuple(String, String, Int32)?
      controller_path = resolve_cakephp_controller_path(routes_file_path, controller_name)
      return unless controller_path && File.exists?(controller_path)

      content = read_file_content(controller_path)
      method_match = content.match(/(?:public|protected|private)\s+function\s+#{action_name}\s*\(/)
      return unless method_match

      method_body = extract_php_method_body_after(content, method_match.begin(0))
      return unless method_body

      body, start_line = method_body
      {body, controller_path, start_line}
    rescue e
      logger.debug "Error resolving CakePHP handler #{controller_name}::#{action_name}: #{e}"
      nil
    end

    private def extract_controller_action_target(options_str : String?) : Tuple(String, String)?
      return unless options_str

      controller_match = options_str.match(/['"]controller['"]\s*=>\s*['"]([^'"]+)['"]/)
      action_match = options_str.match(/['"]action['"]\s*=>\s*['"]([^'"]+)['"]/)
      return unless controller_match && action_match

      controller_name = controller_match[1].strip
      action_name = action_match[1].strip
      return if controller_name.empty? || action_name.empty?
      return unless action_name.match(/\A[A-Za-z_]\w*\z/)

      {controller_name, action_name}
    end

    private def resolve_cakephp_controller_path(routes_file_path : String, controller_name : String) : String?
      marker = "/config/routes.php"
      marker_index = routes_file_path.index(marker)
      return unless marker_index

      relative = cakephp_controller_relative_path(controller_name)
      return unless relative

      File.join(routes_file_path[0...marker_index], "src", "Controller", "#{relative}.php")
    end

    private def cakephp_controller_relative_path(controller_name : String) : String?
      normalized = controller_name.gsub("\\", "/").strip
      segments = normalized.split("/").reject(&.empty?)
      return if segments.empty?
      return if segments.any? { |segment| segment == "." || segment == ".." }

      last_index = segments.size - 1
      last_segment = normalize_controller_segment(segments[last_index])
      return if last_segment.empty?

      segments[last_index] = last_segment.ends_with?("Controller") ? last_segment : "#{last_segment}Controller"
      File.join(segments)
    end

    private def normalize_controller_segment(segment : String) : String
      base = segment.strip
      suffix = "Controller"
      base = base[0...(base.size - suffix.size)] if base.ends_with?(suffix)
      return base if base.match(/[A-Z]/) && !base.includes?("_") && !base.includes?("-")

      String.build do |io|
        base.split(/[_-]/).each do |part|
          next if part.empty?

          io << part[0].upcase
          io << part[1..] if part.size > 1
        end
      end
    end
  end
end
