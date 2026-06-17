require "../../engines/python_engine"

module Analyzer::Python
  class HttpServer < PythonEngine
    # Reference: https://docs.python.org/3/library/http.server.html
    # Reference: https://docs.python.org/3/library/http.server.html#http.server.BaseHTTPRequestHandler
    #
    # http.server is Python's stdlib built-in HTTP server (no third-party framework).
    # Endpoints are defined by subclassing BaseHTTPRequestHandler (or SimpleHTTPRequestHandler)
    # and implementing do_GET / do_POST / do_... methods. The request path is inspected at
    # runtime via `self.path` (commonly combined with urllib.parse.urlparse + parse_qs).
    #
    # This analyzer walks classes inheriting *HTTPRequestHandler, then extracts path literals
    # from inside the do_* methods using conservative, self.path-guarded matching + comment
    # stripping. Param access (query/form/json/header/cookie) is recovered from idiomatic
    # stdlib patterns inside those same methods.
    #
    # Design mirrors Falcon/Tornado (class-based responder walking + parse_code_block) and
    # Crystal::Http (stdlib built-in path/method matching). Does not use the decorator-focused
    # Python route extractors (they target Flask-style @app.get etc.).

    DO_METHODS = {
      "do_get"     => "GET",
      "do_post"    => "POST",
      "do_put"     => "PUT",
      "do_patch"   => "PATCH",
      "do_delete"  => "DELETE",
      "do_head"    => "HEAD",
      "do_options" => "OPTIONS",
      "do_trace"   => "TRACE",
    }

    def analyze
      python_files = get_files_by_extension(".py")
      base_paths.each do |current_base_path|
        python_files.each do |path|
          next unless path_under_root?(path, current_base_path)
          next if path.includes?("/site-packages/")
          next if python_test_path?(path)
          @logger.debug "Analyzing #{path}"

          source = read_file_content(path)
          lines = source.lines
          next unless lines.any? { |l| l.includes?("http.server") || l.includes?("HTTPServer") || l.includes?("BaseHTTPRequestHandler") || l.includes?("SimpleHTTPRequestHandler") || l.includes?("wsgiref.simple_server") }

          analyze_file(path, lines, source, current_base_path)
        end
      end

      result
    end

    private def analyze_file(path : ::String, lines : Array(::String), source : ::String, definition_base_path : ::String)
      # Collect classes that look like http.server request handlers.
      # We accept direct Base/Simple names or any *HTTPRequestHandler (covers subclasses/aliases).
      handler_classes = {} of ::String => Int32 # class_name => 0-based def line

      lines.each_with_index do |line, idx|
        # class Foo(BaseHTTPRequestHandler): or class Foo(http.server.BaseHTTPRequestHandler):
        if m = line.match(/^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*([^\)]*)\s*\)/)
          cls_name = m[1]
          bases = m[2]
          if bases.includes?("HTTPRequestHandler") || bases.includes?("BaseHTTPRequestHandler") || bases.includes?("SimpleHTTPRequestHandler")
            handler_classes[cls_name] = idx
          end
        end
      end

      return if handler_classes.empty?

      handler_classes.each do |_, class_line|
        class_indent = indent_level(lines[class_line])

        i = class_line + 1
        while i < lines.size
          line = lines[i]
          stripped = line.lstrip

          # Stop at dedent to class level (next top-level stmt / class / def).
          if !stripped.empty? && !stripped.starts_with?("#") && indent_level(line) <= class_indent
            break
          end

          # Match do_GET / do_POST etc. (handle optional async just in case)
          if dm = line.match(/^\s*(?:async\s+)?def\s+(do_(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|TRACE))\s*\(/i)
            do_name = dm[1].downcase
            http_method = DO_METHODS[do_name]? || do_name.sub(/^do_/, "").upcase

            codeblock = parse_code_block(lines[i..])
            body_text = codeblock || line
            body_lines = body_text.split("\n")

            # Extract paths guarded by self.path usage inside this handler method only.
            path_hits = extract_paths_from_body(body_lines, i)

            path_hits.each do |p, hit_line|
              normalized = normalize_http_path(p)
              next if normalized.empty?

              endpoint = Endpoint.new(normalized, http_method)
              endpoint.details = Details.new(PathInfo.new(path, hit_line + 1))

              # Parameters from the same do_* body (query, form, json, header, cookie)
              extract_request_params(body_lines, http_method).each do |param|
                endpoint.push_param(param)
              end

              # Callees (only when --include-callee or --ai-context)
              push_callees_from(
                endpoint,
                body_text,
                i, # parse_code_block keeps the def line
                path,
                definition_base_path: definition_base_path,
                source: source
              )

              result << endpoint
            end
          end

          i += 1
        end
      end
    end

    # Quote-aware single-line comment strip. Sufficient for path/parameter lines that
    # contain literal strings for routes or keys (we control the fixture and real-world
    # route guards rarely put the path literal inside a comment on the same line).
    #
    # Uses Char::Reader + byte positions to ensure UTF-8 safety (String slicing with
    # char indices from each_char_with_index would be byte-unsafe on non-ASCII input).
    private def strip_comment(line : ::String) : ::String
      in_double = false
      in_single = false
      escaped = false
      reader = Char::Reader.new(line)
      while reader.has_next?
        ch = reader.current_char
        pos = reader.pos
        if escaped
          escaped = false
        elsif ch == '\\' && (in_double || in_single)
          escaped = true
        elsif ch == '"' && !in_single
          in_double = !in_double
        elsif ch == '\'' && !in_double
          in_single = !in_single
        elsif ch == '#' && !in_double && !in_single
          return line.byte_slice(0, pos)
        end
        reader.next_char
      end
      line
    end

    private def indent_level(line : ::String) : Int32
      line.size - line.lstrip.size
    end

    private def looks_like_http_path(p : ::String) : Bool
      return false if p.empty?
      return false if p.includes?(" ")
      return false if p.size > 200
      p.starts_with?("/")
    end

    private def normalize_http_path(p : ::String) : ::String
      np = p.split("?", 2).first
      np = np.split("#", 2).first
      np = "/" + np unless np.starts_with?("/")
      np = np.gsub(/\/+/, "/")
      np = np[0...-1] if np.ends_with?("/") && np != "/"
      np.empty? ? "/" : np
    end

    # Return Array of {path_literal, absolute_line_index_0based} for paths discovered
    # inside a do_* method body. Only literals that appear on lines also referencing
    # self.path (or urlparse(self.path)) are accepted — prevents picking up unrelated
    # string constants from inside the handler.
    private def extract_paths_from_body(body_lines : Array(::String), body_start : Int32) : Array(Tuple(::String, Int32))
      hits = [] of Tuple(::String, Int32)

      body_lines.each_with_index do |raw, bidx|
        line = strip_comment(raw)
        next if line.strip.empty?

        has_path_ref = line.includes?("self.path") || line.includes?("urlparse(self.path)")

        # self.path == "..." or != or in [ ... ]
        if m = line.match(/self\.path\s*(?:==|!=)\s*[rf]?['"]([^'"]+?)['"]/)
          p = m[1]
          if has_path_ref && looks_like_http_path(p)
            hits << {p, body_start + bidx}
          end
        end
        if m = line.match(/[rf]?['"]([^'"]+?)['"]\s*(?:==|!=)\s*self\.path/)
          p = m[1]
          if has_path_ref && looks_like_http_path(p)
            hits << {p, body_start + bidx}
          end
        end

        # self.path.startswith("...")
        if m = line.match(/self\.path\.startswith\s*\(\s*[rf]?['"]([^'"]+?)['"]/)
          p = m[1]
          if has_path_ref && looks_like_http_path(p)
            hits << {p, body_start + bidx}
          end
        end

        # urlparse(self.path).path == "..."
        if m = line.match(/urlparse\(self\.path\)\.path\s*(?:==|!=)\s*[rf]?['"]([^'"]+?)['"]/)
          p = m[1]
          if has_path_ref && looks_like_http_path(p)
            hits << {p, body_start + bidx}
          end
        end
        if m = line.match(/[rf]?['"]([^'"]+?)['"]\s*(?:==|!=)\s*urlparse\(self\.path\)\.path/)
          p = m[1]
          if has_path_ref && looks_like_http_path(p)
            hits << {p, body_start + bidx}
          end
        end

        # Common pattern: var = urlparse(self.path) ... ; if var.path == "/..." (parsed, p, up etc.)
        # Reverse form too.
        if m = line.match(/\b([A-Za-z_]\w*)\.path\s*(?:==|!=)\s*[rf]?['"]([^'"]+?)['"]/)
          var = m[1]
          p = m[2]
          if (var.downcase.includes?("pars") || var.downcase.includes?("url") || var.downcase.includes?("path") || has_path_ref) && looks_like_http_path(p)
            hits << {p, body_start + bidx}
          end
        end
        if m = line.match(/[rf]?['"]([^'"]+?)['"]\s*(?:==|!=)\s*\b([A-Za-z_]\w*)\.path/)
          var = m[2]
          p = m[1]
          if (var.downcase.includes?("pars") || var.downcase.includes?("url") || var.downcase.includes?("path") || has_path_ref) && looks_like_http_path(p)
            hits << {p, body_start + bidx}
          end
        end

        # list form: if self.path in ["/a", "/b"] (capture literals guarded by self.path mention on line)
        if has_path_ref && line.includes?("self.path")
          line.scan(/[rf]?['"](\/[^'"]*?)['"]/) do |mm|
            p = mm[1]
            if looks_like_http_path(p)
              hits << {p, body_start + bidx}
            end
          end
        end
      end

      hits.uniq
    end

    private def extract_request_params(body_lines : Array(::String), http_method : ::String) : Array(Param)
      params = [] of Param
      seen = Set(::String).new
      body = body_lines.join("\n")

      record = ->(name : ::String, ptype : ::String) do
        key = "#{ptype}:#{name}"
        unless seen.includes?(key)
          params << Param.new(name, "", ptype)
          seen << key
        end
      end

      # Query: parse_qs( ... ).get / [ 'name' ] — covers both direct and urlparse(self.path).query cases.
      # Also track `qs = parse_qs(...)` then `qs.get("name")` / `qs[...]`.
      body.scan(/parse_qs\([^)]*\)\s*\[\s*[rf]?['"]([^'"]+)['"]\s*\]/) do |m|
        record.call(m[1], "query")
      end
      body.scan(/parse_qs\([^)]*\)\s*\.get\s*\(\s*[rf]?['"]([^'"]+)['"]/) do |m|
        record.call(m[1], "query")
      end

      query_vars = [] of ::String
      body.scan(/([A-Za-z_][A-Za-z0-9_]*)\s*=\s*parse_qs\s*\(/) do |m|
        qv = m[1]
        query_vars << qv unless query_vars.includes?(qv)
      end
      query_vars.each do |var|
        body.scan(/#{Regex.escape(var)}\s*\[\s*[rf]?['"]([^'"]+)['"]\s*\]/) do |mm|
          record.call(mm[1], "query")
        end
        body.scan(/#{Regex.escape(var)}\.get\s*\(\s*[rf]?['"]([^'"]+)['"]/) do |mm|
          record.call(mm[1], "query")
        end
      end

      # Header access via self.headers
      body.scan(/self\.headers\s*\[\s*[rf]?['"]([^'"]+)['"]\s*\]/) do |m|
        record.call(m[1], "header")
      end
      body.scan(/self\.headers\.get\s*\(\s*[rf]?['"]([^'"]+)['"]/) do |m|
        record.call(m[1], "header")
      end

      # Cookie via SimpleCookie( self.headers... ) [ 'name' ].value
      body.scan(/SimpleCookie\([^)]*\)\s*\[\s*[rf]?['"]([^'"]+)['"]\s*\]\.value/) do |m|
        record.call(m[1], "cookie")
      end
      # Fallback cookie var access (when var holds the Cookie header value)
      if body.includes?("Cookie") || body.includes?("cookie")
        body.scan(/\b(?:cookie|cookies?)\s*\[\s*[rf]?['"]([^'"]+)['"]\s*\]/i) do |m|
          record.call(m[1], "cookie")
        end
      end

      # Body-bearing methods
      if ["POST", "PUT", "PATCH"].includes?(http_method)
        # form via parse_qs on post body / rfile content
        body.scan(/parse_qs\([^)]*(?:post_body|rfile|body)[^)]*\)\s*\[\s*[rf]?['"]([^'"]+)['"]\s*\]/) do |m|
          record.call(m[1], "form")
        end
        body.scan(/parse_qs\([^)]*(?:post_body|rfile|body)[^)]*\)\s*\.get\s*\(\s*[rf]?['"]([^'"]+)['"]/) do |m|
          record.call(m[1], "form")
        end

        # form via `form = parse_qs(post_body...)` ; form.get / form[...]
        form_vars = [] of ::String
        body.scan(/([A-Za-z_][A-Za-z0-9_]*)\s*=\s*parse_qs\s*\([^)]*(?:post_body|rfile|body)[^)]*\)/) do |m|
          fv = m[1]
          form_vars << fv unless form_vars.includes?(fv)
        end
        form_vars.each do |var|
          body.scan(/#{Regex.escape(var)}\s*\[\s*[rf]?['"]([^'"]+)['"]\s*\]/) do |mm|
            record.call(mm[1], "form")
          end
          body.scan(/#{Regex.escape(var)}\.get\s*\(\s*[rf]?['"]([^'"]+)['"]/) do |mm|
            record.call(mm[1], "form")
          end
        end

        # json: var = json.loads(...) / orjson.loads(...) / ujson.loads(...) then var['k'] / var.get('k')
        json_vars = [] of ::String
        body.scan(/([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:json|orjson|ujson)\.loads?\s*\(/) do |m|
          json_vars << m[1] unless json_vars.includes?(m[1])
        end
        json_vars.each do |var|
          body.scan(/#{Regex.escape(var)}\s*\[\s*[rf]?['"]([^'"]+)['"]\s*\]/) do |mm|
            record.call(mm[1], "json")
          end
          body.scan(/#{Regex.escape(var)}\.get\s*\(\s*[rf]?['"]([^'"]+)['"]/) do |mm|
            record.call(mm[1], "json")
          end
        end
        # direct json.loads(...) / orjson / ujson ['k'] / .get(...) (rare but possible)
        body.scan(/(?:json|orjson|ujson)\.loads?\s*\([^)]*\)\s*\[\s*[rf]?['"]([^'"]+)['"]\s*\]/) do |m|
          record.call(m[1], "json")
        end
        body.scan(/(?:json|orjson|ujson)\.loads?\s*\([^)]*\)\.get\s*\(\s*[rf]?['"]([^'"]+)['"]/) do |m|
          record.call(m[1], "json")
        end
      end

      params
    end
  end
end
