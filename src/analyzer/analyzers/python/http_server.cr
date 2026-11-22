require "../../engines/python_engine"

module Analyzer::Python
  class HttpServer < PythonEngine
    analyzer_for "python_http_server"

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

    # `parsed_vars`/`json_vars` below hold a discovered (but
    # low-cardinality — real code overwhelmingly reuses the same handful of
    # conventional names like `qs`/`data`/`params`) variable name, so the
    # bracket/`.get(...)` access matchers can't be hoisted to constants.
    # Memoize the compiled pair per name across the whole scan instead of
    # rebuilding it every time the name recurs (same handler-body shape
    # across query/form/json access, so one cache serves all three).
    @var_access_regex_cache = Hash(::String, Tuple(Regex, Regex)).new

    FORM_SOURCE_RE             = /\A\s*(?:self\s*\.\s*rfile\b|((?:[A-Za-z_]\w*_)?body(?:_(?:bytes|text|data|raw))?)\b(?!\s*\.\s*query\b))/
    QUERY_SOURCE_ASSIGNMENT_RE = /^\s*([A-Za-z_]\w*)\s*=\s*(?:urlparse\([^\r\n]*?\)|[A-Za-z_]\w*)\s*\.\s*query\b/m

    STDLIB_SERVER_MARKERS_RE = Regex.union(
      "http.server", "HTTPServer", "BaseHTTPRequestHandler",
      "SimpleHTTPRequestHandler", "wsgiref.simple_server",
    )

    private def var_access_regexes(var : ::String) : Tuple(Regex, Regex)
      @var_access_regex_cache[var] ||= {
        /#{Regex.escape(var)}\s*\[\s*[rf]?['"]([^'"]+)['"]\s*\]/,
        /#{Regex.escape(var)}\.get\s*\(\s*[rf]?['"]([^'"]+)['"]/,
      }
    end

    def analyze
      parallel_python_sources do |path, current_base_path|
        @logger.debug "Analyzing #{path}"

        source = read_file_content(path)
        # None of these markers can straddle a newline, so "some line
        # contains one" is exactly "the file contains one" — one
        # precompiled union pass over the buffer replaces five
        # `String#includes?` scans per line, and the `lines` array is only
        # built for files that actually pass.
        next unless content_matches?(source, STDLIB_SERVER_MARKERS_RE)
        lines = source.lines

        analyze_file(path, lines, source, current_base_path)
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
              normalized = Noir::URLPath.request_path(p)
              next if normalized.empty?

              endpoint = Endpoint.new(normalized, http_method)
              endpoint.details = Details.new(PathInfo.new(path, hit_line + 1))

              # Parameters from the same do_* body (query, form, json, header, cookie),
              # minus the branches that guard other paths.
              extract_request_params(lines_without_other_branches(body_lines, path_hits, i, hit_line), http_method).each do |param|
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

    # `body_lines` with the indented blocks that guard the *other* path hits
    # removed, so a branch reads only the params of its own block plus the
    # shared lines around the branches (`qs = parse_qs(...)` above an `if`).
    # A block that holds this hit's line is kept: nested guards share it.
    private def lines_without_other_branches(body_lines : Array(::String), path_hits : Array(Tuple(::String, Int32)), body_start : Int32, hit_line : Int32) : Array(::String)
      return body_lines if path_hits.map(&.[1]).uniq!.size < 2

      own = hit_line - body_start
      skipped = Set(Int32).new
      path_hits.each do |_, other_abs|
        other = other_abs - body_start
        next if other == own || other < 0 || other >= body_lines.size

        branch_indent = indent_level(body_lines[other])
        block_end = other
        (other + 1...body_lines.size).each do |k|
          raw = body_lines[k]
          break if !raw.strip.empty? && indent_level(raw) <= branch_indent
          block_end = k
        end
        next if own >= other && own <= block_end

        (other..block_end).each { |k| skipped << k }
      end
      return body_lines if skipped.empty?

      kept = [] of ::String
      body_lines.each_with_index { |line, k| kept << line unless skipped.includes?(k) }
      kept
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

    # Return Array of {path_literal, absolute_line_index_0based} for paths discovered
    # inside a do_* method body. Only literals that appear on lines also referencing
    # self.path (or urlparse(self.path)) are accepted — prevents picking up unrelated
    # string constants from inside the handler.
    private def extract_paths_from_body(body_lines : Array(::String), body_start : Int32) : Array(Tuple(::String, Int32))
      hits = [] of Tuple(::String, Int32)

      body_lines.each_with_index do |raw, bidx|
        line = strip_python_comment(raw)
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
        if m = line.match(/(?:self|urlparse\(self\.path\)|\w+)\.path\.startswith\s*\(\s*[rf]?['"]([^'"]+?)['"]/)
          p = m[1]
          if has_path_ref && looks_like_http_path(p)
            path_var = find_path_param_in_branch(body_lines, bidx)
            if path_var
              p = "#{p.rstrip('/')}/{#{path_var}}"
            elsif p.ends_with?('/')
              p = "#{p.rstrip('/')}/*"
            end
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

        # list form: if self.path in ["/a", "/b"] (capture literals guarded by self.path membership on line)
        if has_path_ref && (line =~ /\b(?:self|urlparse\(self\.path\)|\w+)\.path\s+(?:not\s+)?in\s*[\[\(\{]/ || line =~ /[\[\(\{][^\]\)\}]*\bin\s+(?:self|urlparse\(self\.path\)|\w+)\.path\b/)
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

    private def find_path_param_in_branch(body_lines : Array(::String), branch_line_idx : Int32) : ::String?
      return if branch_line_idx >= body_lines.size
      branch_indent = indent_level(body_lines[branch_line_idx])

      # Check if path param assignment is on the branch line itself
      line = strip_python_comment(body_lines[branch_line_idx])
      if m = line.match(/\b([A-Za-z_]\w*)\s*=\s*(?:self|\w+)\.path\.(?:rsplit|split)\s*\(\s*[rf]?['"]\/['"]/)
        return m[1]
      elsif m = line.match(/\b([A-Za-z_]\w*)\s*=\s*(?:self|\w+)\.path\.removeprefix\s*\(/)
        return m[1]
      end

      # Scan following lines that belong to this branch (more indented than the branch line)
      (branch_line_idx + 1...body_lines.size).each do |k|
        raw = body_lines[k]
        line = strip_python_comment(raw)
        stripped = line.strip
        next if stripped.empty?

        break if indent_level(raw) <= branch_indent

        if m = line.match(/\b([A-Za-z_]\w*)\s*=\s*(?:self|\w+)\.path\.(?:rsplit|split)\s*\(\s*[rf]?['"]\/['"]/)
          return m[1]
        elsif m = line.match(/\b([A-Za-z_]\w*)\s*=\s*(?:self|\w+)\.path\.removeprefix\s*\(/)
          return m[1]
        end
      end
      nil
    end

    private def extract_request_params(body_lines : Array(::String), http_method : ::String) : Array(Param)
      params = [] of Param
      seen = Set(::String).new
      body = body_lines.join("\n")

      record = ->(name : ::String, ptype : ::String) do
        key = "#{ptype}:#{name}"
        params << Param.new(name, "", ptype) if seen.add?(key)
      end

      body_method = http_method.in?("POST", "PUT", "PATCH")
      query_sources = body.scan(QUERY_SOURCE_ASSIGNMENT_RE).map(&.[1]).to_set
      parse_qs_type = ->(source : ::String) do
        body_source = FORM_SOURCE_RE.match(source) if body_method
        body_source && !query_sources.includes?(body_source[1]?) ? "form" : "query"
      end

      # parse_qs reads both URI query strings and URL-encoded request bodies.
      body.scan(/parse_qs\(([^)]*)\)\s*\[\s*[rf]?['"]([^'"]+)['"]\s*\]/) do |m|
        record.call(m[2], parse_qs_type.call(m[1]))
      end
      body.scan(/parse_qs\(([^)]*)\)\s*\.get\s*\(\s*[rf]?['"]([^'"]+)['"]/) do |m|
        record.call(m[2], parse_qs_type.call(m[1]))
      end

      parsed_vars = Set(Tuple(::String, ::String)).new
      body.scan(/([A-Za-z_][A-Za-z0-9_]*)\s*=\s*parse_qs\s*\(([^)]*)/) do |m|
        parsed_vars << {m[1], parse_qs_type.call(m[2])}
      end
      parsed_vars.each do |var, type|
        bracket_re, get_re = var_access_regexes(var)
        body.scan(bracket_re) do |mm|
          record.call(mm[1], type)
        end
        body.scan(get_re) do |mm|
          record.call(mm[1], type)
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

      if body_method
        # json: var = json.loads(...) / orjson.loads(...) / ujson.loads(...) then var['k'] / var.get('k')
        json_vars = [] of ::String
        body.scan(/([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:json|orjson|ujson)\.loads?\s*\(/) do |m|
          json_vars << m[1] unless json_vars.includes?(m[1])
        end
        json_vars.each do |var|
          bracket_re, get_re = var_access_regexes(var)
          body.scan(bracket_re) do |mm|
            record.call(mm[1], "json")
          end
          body.scan(get_re) do |mm|
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
