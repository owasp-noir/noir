require "../../engines/php_engine"

module Analyzer::Php
  class Slim < PhpEngine
    # ASCII byte values scanned by `find_matching_close_brace` below. Both
    # are < 0x80, so they can never collide with a UTF-8 multi-byte
    # continuation/lead byte (>= 0x80) — same invariant
    # `PhpEngine#find_matching_php_close_brace` relies on.
    private BYTE_LBRACE    = '{'.ord.to_u8
    private BYTE_RBRACE    = '}'.ord.to_u8
    private BYTE_DQUOTE    = '"'.ord.to_u8
    private BYTE_SQUOTE    = '\''.ord.to_u8
    private BYTE_BACKSLASH = '\\'.ord.to_u8

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      return endpoints unless path.ends_with?(".php")
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      content = read_file_content(path)
      if slim_relevant?(content)
        endpoints = analyze_routes_content(content, "", path, include_callee)
      end

      endpoints
    end

    # Precompiled once at load: these four markers used to be four separate
    # `String#includes?` scans of the whole file ORed together. Crystal's
    # `String#includes?` is measurably slower than a single precompiled
    # `Regex#matches?` call, and this runs on every .php file fed into the
    # analyzer during a project-wide scan.
    RELEVANCE_MARKER_RE = /Slim\\|SlimFramework|AppFactory|RouteCollectorProxy/

    # Cheap pre-filter: avoid heavy regex work on files that clearly aren't
    # Slim. Any file that reaches this analyzer via detection is usually in
    # a Slim project, but project-wide scans still feed unrelated PHP here.
    private def slim_relevant?(content : String) : Bool
      content.matches?(RELEVANCE_MARKER_RE) ||
        !!content.match(/\$\w+->(?:get|post|put|patch|delete|options|head|map|group)\s*\(/i)
    end

    private def analyze_routes_content(content : String,
                                       prefix : String,
                                       file_path : String,
                                       include_callee : Bool,
                                       base_line : Int32 = 1) : Array(Endpoint)
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
        group_base_line = base_line + newline_count_before(working_content, after_open_brace)
        new_prefix = build_full_path(prefix, group_prefix)
        endpoints.concat(analyze_routes_content(group_body, new_prefix, file_path, include_callee, group_base_line))

        replacement = "\n" * working_content[match_start...close_end].count('\n')
        working_content = working_content[0...match_start] + replacement + working_content[close_end..]
      end

      # 2. HTTP verb routes: $app->get("/path", handler), $group->post("/items", handler).
      #    Advance `pos` past each matched handler body so nested calls
      #    (e.g. an HTTP client call inside the closure) can't impersonate
      #    a route at the outer level.
      # Keep the path literal on a single line (no quotes, no newlines) so an
      # unrelated `$obj->get('key')` can't pull in following code as a route.
      verb_regex = /(\$\w+)->(get|post|put|patch|delete|options|head)\s*\(\s*['"]([^'"\r\n]+)['"]\s*,/i
      pos = 0
      while m = working_content.match(verb_regex, pos)
        match_text = m[0]
        match_start = working_content.index(match_text, pos)
        break unless match_start
        after_args = match_start + match_text.size

        method = m[2].upcase
        route_path = m[3]
        full_path = build_full_path(prefix, route_path)

        handler_body, next_pos, body_start_line = extract_handler_body_with_end(working_content, after_args, base_line)
        params = extract_brace_path_params(full_path)
        params.concat(extract_handler_params(handler_body)) if handler_body
        params = dedup_params(params)

        endpoint = Endpoint.new(full_path, method, params, details.dup)
        attach_handler_callees(endpoint, handler_body, file_path, body_start_line) if include_callee
        endpoints << endpoint
        pos = next_pos
      end

      # 3. Multi-method map routes: $app->map(["GET","POST"], "/path", handler)
      map_regex = /(\$\w+)->map\s*\(\s*\[([^\]]+)\]\s*,\s*['"]([^'"\r\n]+)['"]\s*,/i
      pos = 0
      while m = working_content.match(map_regex, pos)
        match_text = m[0]
        match_start = working_content.index(match_text, pos)
        break unless match_start
        after_args = match_start + match_text.size

        methods = m[2].scan(/['"]([^'"]+)['"]/).map(&.[1].upcase)

        handler_body, next_pos, body_start_line = extract_handler_body_with_end(working_content, after_args, base_line)
        pos = next_pos

        next if methods.empty?

        route_path = m[3]
        full_path = build_full_path(prefix, route_path)
        handler_params = handler_body ? extract_handler_params(handler_body) : [] of Param

        methods.each do |http_method|
          params = extract_brace_path_params(full_path)
          params.concat(handler_params)
          params = dedup_params(params)
          endpoint = Endpoint.new(full_path, http_method, params, details.dup)
          attach_handler_callees(endpoint, handler_body, file_path, body_start_line) if include_callee
          endpoints << endpoint
        end
      end

      endpoints
    end

    private def attach_handler_callees(endpoint : Endpoint, body : String?, file_path : String, start_line : Int32?)
      return unless body && start_line

      callees = Noir::PhpCalleeExtractor.callees_for_body(body, file_path, start_line)
      attach_php_callees(endpoint, callees)
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

    # Locate the first `$var->group("/prefix", function(...) { ... })` call
    # in the given content and return its span + extracted prefix.
    private def find_group_call(content : String) : Tuple(Int32, Int32, Int32, Int32, String)?
      regex = /(\$\w+)->group\s*\(\s*['"]([^'"]+)['"]\s*,\s*(?:static\s+)?function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?(?::\s*[^{=]+)?\{/i
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
    private def extract_handler_body_with_end(content : String, pos : Int32, base_line : Int32) : Tuple(String?, Int32, Int32?)
      return {nil, pos, nil} unless pos < content.size

      scan_pos = pos
      while scan_pos < content.size && content[scan_pos].ascii_whitespace?
        scan_pos += 1
      end
      return {nil, pos, nil} unless scan_pos < content.size

      closure_regex = /\A(?:static\s+)?function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?(?::\s*[^{=]+)?\{/i
      m = content[scan_pos..].match(closure_regex)
      return {nil, pos, nil} unless m

      brace_pos = scan_pos + m[0].size - 1
      body_end = find_matching_close_brace(content, brace_pos)
      return {nil, pos, nil} unless body_end

      body_start_line = base_line + newline_count_before(content, brace_pos)
      {content[(brace_pos + 1)...body_end], body_end + 1, body_start_line}
    end

    private def newline_count_before(content : String, pos : Int32) : Int32
      return 0 if pos <= 0

      content[0...pos].count('\n')
    end

    # Byte-level scan for O(1) positional access instead of the previous
    # `String#[](Int)` per-character loop, which is O(n) on any string
    # containing a multi-byte UTF-8 character and turned a single call into
    # O(n^2) — see `PhpEngine#find_matching_php_close_brace` for the same
    # fix applied to the shared brace matcher. `find_group_call` and
    # `extract_handler_body_with_end` both call this over the full
    # remainder of the file, so this is the hot path for any Slim routes
    # file with non-ASCII content (e.g. CJK comments/strings).
    private def find_matching_close_brace(content : String, open_pos : Int32) : Int32?
      bytes = content.to_slice
      start = content.char_index_to_byte_index(open_pos)
      return unless start && start < bytes.size && bytes[start] == BYTE_LBRACE

      depth = 0
      in_string = false
      quote_byte = 0_u8
      pos = start
      size = bytes.size
      while pos < size
        byte = bytes[pos]
        if !in_string
          case byte
          when BYTE_LBRACE
            depth += 1
          when BYTE_RBRACE
            depth -= 1
            return content.byte_index_to_char_index(pos) if depth == 0
          when BYTE_DQUOTE, BYTE_SQUOTE
            in_string = true
            quote_byte = byte
          end
        elsif byte == BYTE_BACKSLASH
          pos += 1
        elsif byte == quote_byte
          in_string = false
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
