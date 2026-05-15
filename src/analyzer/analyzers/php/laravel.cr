require "../../engines/php_engine"

module Analyzer::Php
  class Laravel < PhpEngine
    def analyze_file(path : String) : Array(Endpoint)
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
      include_callee = any_to_bool(@options["include_callee"]?)
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
          params = extract_brace_path_params(route_path)
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

    private def analyze_routes_content(content : String,
                                       prefix : String,
                                       file_path : String,
                                       include_callee : Bool,
                                       base_line : Int32 = 1) : Array(Endpoint)
      endpoints = [] of Endpoint

      # 1. Simple routes: Route::get, Route::post, etc.
      verb_regex = /Route::(get|post|put|patch|delete|options|head)\s*\(\s*['"]([^'"]+)['"]\s*,/mi
      pos = 0
      while route_match = content.match(verb_regex, pos)
        methods = [route_match[1].upcase]
        route_path = route_match[2]
        full_path = build_full_path(prefix, route_path)
        route_line = base_line + newline_count_before(content, route_match.begin(0))
        handler_body, next_pos, body_start_line = extract_inline_closure_body(content, route_match.end(0), base_line)
        params = extract_brace_path_params(full_path)

        methods.each do |http_method|
          details = Details.new(PathInfo.new(file_path, route_line))
          endpoint = Endpoint.new(full_path, http_method, params, details.dup)
          attach_route_callees(endpoint, handler_body, file_path, body_start_line) if include_callee
          endpoints << endpoint
        end
        pos = next_pos
      end

      match_regex = /Route::match\s*\(\s*\[([^\]]+)\]\s*,\s*['"]([^'"]+)['"]\s*,/mi
      pos = 0
      while route_match = content.match(match_regex, pos)
        methods = extract_methods_from_array(route_match[1])
        route_path = route_match[2]
        full_path = build_full_path(prefix, route_path)
        route_line = base_line + newline_count_before(content, route_match.begin(0))
        handler_body, next_pos, body_start_line = extract_inline_closure_body(content, route_match.end(0), base_line)
        params = extract_brace_path_params(full_path)

        methods.each do |http_method|
          details = Details.new(PathInfo.new(file_path, route_line))
          endpoint = Endpoint.new(full_path, http_method, params, details.dup)
          attach_route_callees(endpoint, handler_body, file_path, body_start_line) if include_callee
          endpoints << endpoint
        end
        pos = next_pos
      end

      any_regex = /Route::any\s*\(\s*['"]([^'"]+)['"]\s*,/mi
      pos = 0
      while route_match = content.match(any_regex, pos)
        methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"]
        route_path = route_match[1]
        full_path = build_full_path(prefix, route_path)
        route_line = base_line + newline_count_before(content, route_match.begin(0))
        handler_body, next_pos, body_start_line = extract_inline_closure_body(content, route_match.end(0), base_line)
        params = extract_brace_path_params(full_path)

        methods.each do |http_method|
          details = Details.new(PathInfo.new(file_path, route_line))
          endpoint = Endpoint.new(full_path, http_method, params, details.dup)
          attach_route_callees(endpoint, handler_body, file_path, body_start_line) if include_callee
          endpoints << endpoint
        end
        pos = next_pos
      end

      # 2. Resource routes
      resource_matches = content.scan(/Route::resource\s*\(\s*['"]([^'"]+)['"][^)]*\)/mi)
      resource_matches.each do |match|
        resource_name = match[1]
        full_resource_path = build_full_path(prefix, resource_name)
        route_line = base_line + newline_count_before(content, match.begin(0))
        endpoints.concat(create_resource_endpoints(full_resource_path.lstrip('/'), file_path, route_line))
      end

      api_resource_matches = content.scan(/Route::apiResource\s*\(\s*['"]([^'"]+)['"][^)]*\)/mi)
      api_resource_matches.each do |match|
        resource_name = match[1]
        full_resource_path = build_full_path(prefix, resource_name)
        route_line = base_line + newline_count_before(content, match.begin(0))
        endpoints.concat(create_api_resource_endpoints(full_resource_path.lstrip('/'), file_path, route_line))
      end

      # 3. Group routes (recursive)
      # Route::prefix(...)->group(...)
      fluent_group_matches = content.scan(/Route::prefix\s*\(\s*['"]([^'"]+)['"]\s*\)->group\s*\(\s*function\s*\([^)]*\)\s*\{((?:[^{}]|{[^{}]*})*)\}/mi)
      fluent_group_matches.each do |match|
        group_prefix = match[1]
        group_content = match[2]
        group_base_line = base_line + newline_count_before(content, match.begin(2))
        new_prefix = build_full_path(prefix, group_prefix)
        endpoints.concat(analyze_routes_content(group_content, new_prefix, file_path, include_callee, group_base_line))
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

        group_base_line = base_line + newline_count_before(content, match.begin(2))
        endpoints.concat(analyze_routes_content(group_content, new_prefix, file_path, include_callee, group_base_line))
      end

      # Simple group with no prefix: Route::group(function() { ... })
      simple_group_matches = content.scan(/Route::group\s*\(\s*function\s*\([^)]*\)\s*\{((?:[^{}]|{[^{}]*})*)\}/mi)
      simple_group_matches.each do |match|
        group_content = match[1]
        group_base_line = base_line + newline_count_before(content, match.begin(1))
        endpoints.concat(analyze_routes_content(group_content, prefix, file_path, include_callee, group_base_line))
      end

      endpoints
    end

    private def attach_route_callees(endpoint : Endpoint, body : String?, file_path : String, start_line : Int32?)
      return unless body && start_line

      callees = Noir::PhpCalleeExtractor.callees_for_body(body, file_path, start_line)
      attach_php_callees(endpoint, callees)
    end

    private def extract_inline_closure_body(content : String, pos : Int32, base_line : Int32) : Tuple(String?, Int32, Int32?)
      return {nil, pos, nil} unless pos < content.size

      scan_pos = pos
      while scan_pos < content.size && content[scan_pos].ascii_whitespace?
        scan_pos += 1
      end
      return {nil, pos, nil} unless scan_pos < content.size

      closure_regex = /\A(?:static\s+)?function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?(?::\s*[^{=]+)?\{/i
      match = content[scan_pos..].match(closure_regex)
      return extract_arrow_closure_body(content, scan_pos, pos, base_line) unless match

      brace_pos = scan_pos + match[0].size - 1
      body_end = find_matching_php_close_brace(content, brace_pos)
      return {nil, pos, nil} unless body_end

      body_start_line = base_line + newline_count_before(content, brace_pos)
      {content[(brace_pos + 1)...body_end], body_end + 1, body_start_line}
    end

    private def extract_arrow_closure_body(content : String,
                                           scan_pos : Int32,
                                           fallback_pos : Int32,
                                           base_line : Int32) : Tuple(String?, Int32, Int32?)
      arrow_regex = /\A(?:static\s+)?fn\s*\([^)]*\)\s*(?::\s*[^=]+)?=>/i
      match = content[scan_pos..].match(arrow_regex)
      return {nil, fallback_pos, nil} unless match

      body_start = scan_pos + match[0].size
      body_end = find_arrow_expression_end(content, body_start)
      return {nil, fallback_pos, nil} unless body_end > body_start

      body_start_line = base_line + newline_count_before(content, body_start)
      {content[body_start...body_end], body_end, body_start_line}
    end

    private def find_arrow_expression_end(content : String, start_pos : Int32) : Int32
      paren_depth = 0
      bracket_depth = 0
      brace_depth = 0
      in_string = false
      in_line_comment = false
      in_block_comment = false
      escaped = false
      quote = '\0'
      pos = start_pos

      while pos < content.size
        char = content[pos]
        next_char = content[pos + 1]?

        if in_line_comment
          in_line_comment = false if char == '\n'
        elsif in_block_comment
          if char == '*' && next_char == '/'
            in_block_comment = false
            pos += 1
          end
        elsif in_string
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            in_string = false
          end
        elsif char == '/' && next_char == '/'
          in_line_comment = true
          pos += 1
        elsif char == '/' && next_char == '*'
          in_block_comment = true
          pos += 1
        elsif char == '#'
          in_line_comment = true
        elsif char == '"' || char == '\''
          in_string = true
          quote = char
        elsif char == '('
          paren_depth += 1
        elsif char == ')'
          return pos if paren_depth == 0 && bracket_depth == 0 && brace_depth == 0
          paren_depth -= 1 if paren_depth > 0
        elsif char == ',' || char == ';'
          return pos if paren_depth == 0 && bracket_depth == 0 && brace_depth == 0
        elsif char == '['
          bracket_depth += 1
        elsif char == ']'
          return pos if paren_depth == 0 && bracket_depth == 0 && brace_depth == 0
          bracket_depth -= 1 if bracket_depth > 0
        elsif char == '{'
          brace_depth += 1
        elsif char == '}'
          return pos if paren_depth == 0 && bracket_depth == 0 && brace_depth == 0
          brace_depth -= 1 if brace_depth > 0
        end

        pos += 1
      end

      content.size
    end

    private def newline_count_before(content : String, pos : Int32) : Int32
      return 0 if pos <= 0

      content[0...pos].count('\n')
    end

    private def create_resource_endpoints(resource : String, file_path : String, line : Int32? = nil) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(file_path, line))

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
        params = extract_brace_path_params(path)
        endpoints << Endpoint.new(path, method, params, details)
      end

      endpoints
    end

    private def create_api_resource_endpoints(resource : String, file_path : String, line : Int32? = nil) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(file_path, line))

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
        params = extract_brace_path_params(path)
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
  end
end
