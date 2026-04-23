require "../../engines/php_engine"

module Analyzer::Php
  class Slim < PhpEngine
    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      return endpoints unless path.ends_with?(".php")

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end
        next unless slim_relevant?(content)
        endpoints = analyze_routes_content(content, "", path)
      end

      endpoints
    end

    # Cheap pre-filter: avoid heavy regex work on files that clearly aren't
    # Slim. Any file that reaches this analyzer via detection is usually in
    # a Slim project, but project-wide scans still feed unrelated PHP here.
    private def slim_relevant?(content : String) : Bool
      content.includes?("Slim\\") ||
        content.includes?("SlimFramework") ||
        content.includes?("AppFactory") ||
        content.includes?("RouteCollectorProxy") ||
        !!content.match(/\$\w+->(?:get|post|put|patch|delete|options|head|map|group)\s*\(/i)
    end

    private def analyze_routes_content(content : String, prefix : String, file_path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(file_path))

      working_content = content

      # 1. Recursively extract group blocks: $app->group("/prefix", function(...) { ... })
      #    Removing each group body from working_content prevents the verb pass
      #    below from double-counting its nested routes.
      loop do
        info = find_group_call(working_content)
        break unless info

        match_start, after_open_brace, body_end, close_end, group_prefix = info
        group_body = working_content[after_open_brace...body_end]
        new_prefix = build_full_path(prefix, group_prefix)
        endpoints.concat(analyze_routes_content(group_body, new_prefix, file_path))

        working_content = working_content[0...match_start] + working_content[close_end..]
      end

      # 2. HTTP verb routes: $app->get("/path", handler), $group->post("/items", handler).
      #    Advance `pos` past each matched handler body so nested calls
      #    (e.g. an HTTP client call inside the closure) can't impersonate
      #    a route at the outer level.
      verb_regex = /(\$\w+)->(get|post|put|patch|delete|options|head)\s*\(\s*['"]([^'"]+)['"]\s*,/i
      pos = 0
      while m = working_content.match(verb_regex, pos)
        match_text = m[0]
        match_start = working_content.index(match_text, pos)
        break unless match_start
        after_args = match_start + match_text.size

        method = m[2].upcase
        route_path = m[3]
        full_path = build_full_path(prefix, route_path)

        handler_body, next_pos = extract_handler_body_with_end(working_content, after_args)
        params = extract_brace_path_params(full_path)
        params.concat(extract_handler_params(handler_body)) if handler_body

        endpoints << Endpoint.new(full_path, method, params, details.dup)
        pos = next_pos
      end

      # 3. Multi-method map routes: $app->map(["GET","POST"], "/path", handler)
      map_regex = /(\$\w+)->map\s*\(\s*\[([^\]]+)\]\s*,\s*['"]([^'"]+)['"]\s*,/i
      pos = 0
      while m = working_content.match(map_regex, pos)
        match_text = m[0]
        match_start = working_content.index(match_text, pos)
        break unless match_start
        after_args = match_start + match_text.size

        methods = m[2].scan(/['"]([^'"]+)['"]/).map(&.[1].upcase)

        handler_body, next_pos = extract_handler_body_with_end(working_content, after_args)
        pos = next_pos

        next if methods.empty?

        route_path = m[3]
        full_path = build_full_path(prefix, route_path)
        handler_params = handler_body ? extract_handler_params(handler_body) : [] of Param

        methods.each do |http_method|
          params = extract_brace_path_params(full_path)
          params.concat(handler_params)
          endpoints << Endpoint.new(full_path, http_method, params, details.dup)
        end
      end

      endpoints
    end

    # Locate the first `$var->group("/prefix", function(...) { ... })` call
    # in the given content and return its span + extracted prefix.
    private def find_group_call(content : String) : Tuple(Int32, Int32, Int32, Int32, String)?
      regex = /(\$\w+)->group\s*\(\s*['"]([^'"]+)['"]\s*,\s*function\s*\([^)]*\)\s*(?::\s*[^{]+)?\{/i
      m = content.match(regex)
      return unless m

      match_text = m[0]
      match_start = content.index(match_text)
      return unless match_start

      brace_pos = match_start + match_text.size - 1
      body_end = find_matching_close_brace(content, brace_pos)
      return unless body_end

      # Consume the closing `)` (and optional `;`) that terminates the group call.
      close_end = body_end + 1
      while close_end < content.size && content[close_end].ascii_whitespace?
        close_end += 1
      end
      if close_end < content.size && content[close_end] == ')'
        close_end += 1
        if close_end < content.size && content[close_end] == ';'
          close_end += 1
        end
      end

      {match_start, brace_pos + 1, body_end, close_end, m[2]}
    end

    # Scan forward from `pos` to find the immediate handler closure body,
    # if the handler is an inline `function(...) { ... }`. Returns the body
    # text (or nil when the handler is a string/callable or brace matching
    # fails) together with the position after the handler so the caller can
    # resume scanning past it.
    private def extract_handler_body_with_end(content : String, pos : Int32) : Tuple(String?, Int32)
      return {nil, pos} unless pos < content.size

      scan_pos = pos
      while scan_pos < content.size && content[scan_pos].ascii_whitespace?
        scan_pos += 1
      end
      return {nil, pos} unless scan_pos < content.size

      closure_regex = /\A(?:static\s+)?(?:function|fn)\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?(?::\s*[^{=]+)?\{/i
      m = content[scan_pos..].match(closure_regex)
      return {nil, pos} unless m

      brace_pos = scan_pos + m[0].size - 1
      body_end = find_matching_close_brace(content, brace_pos)
      return {nil, pos} unless body_end

      {content[(brace_pos + 1)...body_end], body_end + 1}
    end

    private def find_matching_close_brace(content : String, open_pos : Int32) : Int32?
      return unless open_pos < content.size && content[open_pos] == '{'

      depth = 1
      pos = open_pos + 1
      while pos < content.size
        case content[pos]
        when '{'
          depth += 1
        when '}'
          depth -= 1
          return pos if depth == 0
        end
        pos += 1
      end

      nil
    end

    PARAM_PATTERNS = [
      {/\$args\s*\[\s*['"]([^'"]+)['"]\s*\]/, "path"},
      {/->getQueryParams\s*\(\s*\)\s*\[\s*['"]([^'"]+)['"]\s*\]/, "query"},
      {/->getParsedBody\s*\(\s*\)\s*\[\s*['"]([^'"]+)['"]\s*\]/, "form"},
      {/->getHeaderLine\s*\(\s*['"]([^'"]+)['"]\s*\)/, "header"},
      {/->getHeader\s*\(\s*['"]([^'"]+)['"]\s*\)/, "header"},
      {/->getCookieParams\s*\(\s*\)\s*\[\s*['"]([^'"]+)['"]\s*\]/, "cookie"},
    ]

    # Extract request-parameter references from a handler body. Skips
    # duplicates within the same handler so the endpoint param list reflects
    # distinct inputs instead of repeated reads.
    private def extract_handler_params(body : String) : Array(Param)
      params = [] of Param
      seen = Set(String).new

      PARAM_PATTERNS.each do |entry|
        pattern, type = entry
        body.scan(pattern) do |m|
          name = m[1]
          key = "#{type}:#{name}"
          next if seen.includes?(key)
          params << Param.new(name, "", type)
          seen.add(key)
        end
      end

      params
    end
  end
end
