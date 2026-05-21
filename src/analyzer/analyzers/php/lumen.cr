require "../../engines/php_engine"

module Analyzer::Php
  # Lumen is Laravel's micro-framework. Routes are registered against an
  # injected `$router` (not the Laravel `Route::` facade), and groups carry
  # their prefix in an associative array — `$router->group(['prefix' => 'x'],
  # function () use ($router) { ... })`. That's a distinct enough shape from
  # Laravel's facade-style routing that it gets its own analyzer rather than
  # extending `Laravel`.
  class Lumen < PhpEngine
    private struct RouteGroup
      getter prefix, body, body_start, body_end

      def initialize(@prefix : String, @body : String, @body_start : Int32, @body_end : Int32)
      end
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      return endpoints unless path.ends_with?(".php")

      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end
        next unless lumen_relevant?(content)
        endpoints = analyze_routes_content(content, "", path, include_callee)
      end

      endpoints
    end

    # Cheap pre-filter so a project-wide PHP scan doesn't burn regex time on
    # every unrelated `.php` file feeding into the analyzer.
    private def lumen_relevant?(content : String) : Bool
      return true if content.includes?("Laravel\\Lumen")
      !!content.match(/\$router\s*->\s*(?:get|post|put|patch|delete|options|head|group|addRoute)\s*\(/i)
    end

    private def analyze_routes_content(content : String,
                                       prefix : String,
                                       file_path : String,
                                       include_callee : Bool,
                                       base_line : Int32 = 1) : Array(Endpoint)
      endpoints = [] of Endpoint
      route_groups = extract_route_groups(content)

      # 1. Verb routes: $router->get('/path', handler)
      verb_regex = /\$router\s*->\s*(get|post|put|patch|delete|options|head)\s*\(\s*['"]([^'"]+)['"]\s*,/mi
      pos = 0
      loop do
        route_match = content.match(verb_regex, pos)
        break unless route_match

        if inside_group_body?(route_match.begin(0), route_groups)
          pos = route_match.end(0)
          next
        end

        method = route_match[1].upcase
        route_path = route_match[2]
        full_path = build_full_path(prefix, route_path)
        route_line = base_line + newline_count_before(content, route_match.begin(0))

        handler_body, next_pos, body_start_line = extract_inline_closure_body(content, route_match.end(0), base_line)
        params = extract_brace_path_params(full_path)
        params.concat(extract_handler_params(handler_body)) if handler_body
        params = dedup_params(params)

        details = Details.new(PathInfo.new(file_path, route_line))
        endpoint = Endpoint.new(full_path, method, params, details.dup)
        attach_route_callees(endpoint, handler_body, file_path, body_start_line) if include_callee
        endpoints << endpoint
        pos = next_pos
      end

      # 2. Generic addRoute: $router->addRoute(['GET','POST'], '/path', handler)
      add_route_regex = /\$router\s*->\s*addRoute\s*\(\s*\[([^\]]+)\]\s*,\s*['"]([^'"]+)['"]\s*,/mi
      pos = 0
      loop do
        route_match = content.match(add_route_regex, pos)
        break unless route_match

        if inside_group_body?(route_match.begin(0), route_groups)
          pos = route_match.end(0)
          next
        end

        methods = extract_methods_from_array(route_match[1])
        route_path = route_match[2]
        full_path = build_full_path(prefix, route_path)
        route_line = base_line + newline_count_before(content, route_match.begin(0))

        handler_body, next_pos, body_start_line = extract_inline_closure_body(content, route_match.end(0), base_line)
        handler_params = handler_body ? extract_handler_params(handler_body) : [] of Param

        methods.each do |http_method|
          params = extract_brace_path_params(full_path)
          params.concat(handler_params)
          params = dedup_params(params)

          details = Details.new(PathInfo.new(file_path, route_line))
          endpoint = Endpoint.new(full_path, http_method, params, details.dup)
          attach_route_callees(endpoint, handler_body, file_path, body_start_line) if include_callee
          endpoints << endpoint
        end
        pos = next_pos
      end

      # 3. Recurse into groups so nested route registrations pick up the
      #    accumulated prefix without the outer pass also emitting them.
      route_groups.each do |group|
        new_prefix = group.prefix.empty? ? prefix : build_full_path(prefix, group.prefix)
        group_base_line = base_line + newline_count_before(content, group.body_start)
        endpoints.concat(analyze_routes_content(group.body, new_prefix, file_path, include_callee, group_base_line))
      end

      endpoints
    end

    private def extract_route_groups(content : String) : Array(RouteGroup)
      groups = [] of RouteGroup
      group_regex = /\$router\s*->\s*group\s*\(/mi
      pos = 0

      loop do
        group_match = content.match(group_regex, pos)
        break unless group_match

        info = extract_group_array_and_closure(content, group_match.end(0))
        if info
          prefix, body, body_start, body_end, after = info
          groups << RouteGroup.new(prefix, body, body_start, body_end)
          pos = after
        else
          pos = group_match.end(0)
        end
      end

      groups
    end

    # Walk from just past `$router->group(` through the leading attributes
    # array and into the closure body. Returns nil if the structure looks
    # malformed so the outer loop can skip past safely.
    private def extract_group_array_and_closure(content : String, pos : Int32) : Tuple(String, String, Int32, Int32, Int32)?
      scan_pos = skip_whitespace(content, pos)
      return unless scan_pos < content.size

      attr_prefix = ""

      if content[scan_pos]? == '['
        array_end = find_matching_bracket(content, scan_pos)
        return unless array_end

        attr_text = content[(scan_pos + 1)...array_end]
        attr_prefix = extract_prefix_from_array(attr_text)
        scan_pos = skip_whitespace(content, array_end + 1)
        return unless scan_pos < content.size && content[scan_pos] == ','

        scan_pos = skip_whitespace(content, scan_pos + 1)
      end

      closure_regex = /\A(?:static\s+)?function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?(?::\s*[^{=]+)?\{/i
      match = content[scan_pos..].match(closure_regex)
      return unless match

      brace_pos = scan_pos + match[0].size - 1
      body_end = find_matching_php_close_brace(content, brace_pos)
      return unless body_end

      after = body_end + 1
      while after < content.size && content[after].ascii_whitespace?
        after += 1
      end
      after += 1 if after < content.size && content[after] == ')'
      after += 1 if after < content.size && content[after] == ';'

      {attr_prefix, content[(brace_pos + 1)...body_end], brace_pos + 1, body_end, after}
    end

    private def extract_prefix_from_array(attr_text : String) : String
      if m = attr_text.match(/['"]prefix['"]\s*=>\s*['"]([^'"]*)['"]/i)
        return m[1]
      end
      ""
    end

    private def find_matching_bracket(content : String, open_pos : Int32) : Int32?
      return unless open_pos < content.size && content[open_pos] == '['

      depth = 0
      in_string = false
      quote = '\0'
      escaped = false
      pos = open_pos

      while pos < content.size
        char = content[pos]
        if in_string
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            in_string = false
          end
        elsif char == '"' || char == '\''
          in_string = true
          quote = char
        elsif char == '['
          depth += 1
        elsif char == ']'
          depth -= 1
          return pos if depth == 0
        end
        pos += 1
      end

      nil
    end

    private def skip_whitespace(content : String, pos : Int32) : Int32
      while pos < content.size && content[pos].ascii_whitespace?
        pos += 1
      end
      pos
    end

    private def inside_group_body?(pos : Int32, groups : Array(RouteGroup)) : Bool
      groups.any? { |group| pos >= group.body_start && pos < group.body_end }
    end

    private def extract_inline_closure_body(content : String, pos : Int32, base_line : Int32) : Tuple(String?, Int32, Int32?)
      return {nil, pos, nil} unless pos < content.size

      scan_pos = skip_whitespace(content, pos)
      return {nil, pos, nil} unless scan_pos < content.size

      closure_regex = /\A(?:static\s+)?function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?(?::\s*[^{=]+)?\{/i
      match = content[scan_pos..].match(closure_regex)
      return {nil, pos, nil} unless match

      brace_pos = scan_pos + match[0].size - 1
      body_end = find_matching_php_close_brace(content, brace_pos)
      return {nil, pos, nil} unless body_end

      body_start_line = base_line + newline_count_before(content, brace_pos)
      {content[(brace_pos + 1)...body_end], body_end + 1, body_start_line}
    end

    private def attach_route_callees(endpoint : Endpoint, body : String?, file_path : String, start_line : Int32?)
      return unless body && start_line

      callees = Noir::PhpCalleeExtractor.callees_for_body(body, file_path, start_line)
      attach_php_callees(endpoint, callees)
    end

    private def newline_count_before(content : String, pos : Int32) : Int32
      return 0 if pos <= 0

      content[0...pos].count('\n')
    end

    private def extract_methods_from_array(methods_str : String) : Array(String)
      methods = [] of String
      methods_str.scan(/['"]([^'"]+)['"]/).each do |match|
        methods << match[1].upcase
      end
      methods
    end

    HANDLER_PARAM_PATTERNS = [
      {/\$request\s*->\s*input\s*\(\s*['"]([^'"]+)['"]/, "form"},
      {/\$request\s*->\s*post\s*\(\s*['"]([^'"]+)['"]/, "form"},
      {/\$request\s*->\s*get\s*\(\s*['"]([^'"]+)['"]/, "query"},
      {/\$request\s*->\s*query\s*\(\s*['"]([^'"]+)['"]/, "query"},
      {/\$request\s*->\s*header\s*\(\s*['"]([^'"]+)['"]/, "header"},
      {/\$request\s*->\s*cookie\s*\(\s*['"]([^'"]+)['"]/, "cookie"},
      {/\$request\s*->\s*file\s*\(\s*['"]([^'"]+)['"]/, "form"},
    ]

    private def extract_handler_params(body : String) : Array(Param)
      params = [] of Param
      HANDLER_PARAM_PATTERNS.each do |entry|
        pattern, type = entry
        body.scan(pattern).each do |m|
          params << Param.new(m[1], "", type)
        end
      end
      params
    end

    private def dedup_params(params : Array(Param)) : Array(Param)
      seen = Set(String).new
      params.select do |param|
        key = "#{param.param_type}\0#{param.name}"
        if seen.includes?(key)
          false
        else
          seen.add(key)
          true
        end
      end
    end
  end
end
