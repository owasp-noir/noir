require "../../engines/ruby_engine"

module Analyzer::Ruby
  class Webrick < RubyEngine
    # Reference: https://ruby-doc.org/stdlib/libdoc/webrick/rdoc/WEBrick.html
    # WEBrick::HTTPServer#mount_proc + #mount + HTTPServlet::AbstractServlet (do_GET etc.)
    #
    # Webrick is Ruby's stdlib HTTP server (no third-party gem in normal cases).
    # Routes are declared via mount_proc("PATH") { |req,res| ... } or
    # mount("PATH", MyServlet) where class MyServlet < WEBrick::HTTPServlet::AbstractServlet
    # defines do_GET / do_POST etc.
    #
    # This analyzer:
    # - Pre-indexes servlet classes across all files (supports def-after-mount and simple multi-file).
    # - Emits endpoints from the declarative mount paths (primary signal).
    # - Extracts verbs inside mount_proc blocks by scanning request_method guards (case/when/if ==).
    # - Extracts params only from the handler body (query/header/cookie + form/json on body for mutating verbs).
    # - Skips FileHandler mounts (static).
    # - Supports req/request, res/response naming.
    # - Reuses RubyEngine helpers (parallel_file_scan, ruby_non_production_path?, extract_ruby_do_block, attach, normalize).
    # - Does not chase runtime req.path branches inside handlers for sub-paths (keeps v1 conservative + matches issue examples).

    SERVLET_METHODS = {
      "do_get"     => "GET",
      "do_post"    => "POST",
      "do_put"     => "PUT",
      "do_patch"   => "PATCH",
      "do_delete"  => "DELETE",
      "do_head"    => "HEAD",
      "do_options" => "OPTIONS",
    }

    def analyze
      include_callee = callees_needed?

      # Cross-file servlet index (class name -> do_ methods with bodies).
      # Mirrors Grape's build_*_index approach for mountable handlers.
      servlet_index = build_servlet_index

      parallel_file_scan do |path|
        next unless path.ends_with?(".rb") || path.ends_with?(".ru")
        next if ruby_non_production_path?(path)
        content = read_file_content(path)
        # Gate early on webrick signals (avoid unnecessary work + comment-only noise)
        next unless content.includes?("webrick") || content.includes?("WEBrick") || content.includes?("mount_proc")
        process_webrick_file(path, content, servlet_index, include_callee)
      end

      @result
    end

    private def build_servlet_index : Hash(String, Hash(String, {line: Int32, body: String}))
      index = {} of String => Hash(String, {line: Int32, body: String})

      all_files.each do |path|
        next unless path.ends_with?(".rb") || path.ends_with?(".ru")
        next if ruby_non_production_path?(path)
        next if File.directory?(path)
        next unless File.exists?(path)

        content = read_file_content(path)
        next unless content.includes?("AbstractServlet")

        lines = content.lines
        i = 0
        while i < lines.size
          line = lines[i]
          # Match common inheritance forms
          if m = line.match(/^\s*class\s+([A-Z][A-Za-z0-9_]*)\s*<\s*(?:(?:WEBrick::)?HTTPServlet::)?AbstractServlet\b/)
            cls = m[1]
            cls_indent = line.size - line.lstrip.size
            methods = {} of String => {line: Int32, body: String}
            j = i + 1
            while j < lines.size
              l = lines[j]
              lind = l.size - l.lstrip.size
              if !l.strip.empty? && !l.strip.starts_with?("#") && lind <= cls_indent
                break
              end
              if dm = l.match(/^\s*def\s+(do_(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS))\s*\(/i)
                do_name = dm[1].downcase
                # Collect method body: from this line to matching end at same-or-less indent
                body_lines = [] of String
                k = j
                depth = 0
                while k < lines.size
                  kl = lines[k]
                  kstrip = Noir::RubyCalleeExtractor.strip_comment(kl, preserve_strings: false).strip
                  kind = kl.size - kl.lstrip.size
                  if k > j
                    if kstrip == "end" || kstrip.starts_with?("end ")
                      if kind <= lind
                        depth -= 1
                        if depth <= 0
                          break
                        end
                      end
                    end
                  end
                  # track do / def / if etc for rough depth (reuse engine helper where possible)
                  depth += ruby_do_block_open_delta(kstrip) if k > j
                  body_lines << kl
                  k += 1
                end
                body = body_lines.join("\n")
                methods[do_name] = {line: j, body: body}
                j = k
                next
              end
              j += 1
            end
            unless methods.empty?
              index[cls] = methods
            end
            i = j
            next
          end
          i += 1
        end
      end

      index
    end

    private def process_webrick_file(path : String, content : String, servlet_index : Hash(String, Hash(String, {line: Int32, body: String})), include_callee : Bool)
      lines = content.lines

      lines.each_with_index do |raw, idx|
        next unless raw.valid_encoding?
        stripped = Noir::RubyCalleeExtractor.strip_comment(raw, preserve_strings: true).strip
        next if stripped.empty? || stripped.starts_with?('#')

        # mount_proc "PATH" [ , proc ] do |req,res| ... end
        # Support both mount_proc("..") and mount_proc ".." (no parens, common in examples)
        if m = stripped.match(/\.mount_proc\s*\(?\s*['"]([^'"]+)['"]/)
          raw_path = m[1]
          mount_path = normalize_webrick_path(raw_path)
          # Try to grab the block body for verbs + params + callees
          handler_body = ""
          handler_start_line = idx + 1
          verbs_found = [] of String

          if block = extract_ruby_do_block(lines, idx)
            b, bs = block
            handler_body = b
            handler_start_line = bs
            verbs_found = extract_verbs_from_handler_body(handler_body)
          end

          verbs_found = ["GET"] if verbs_found.empty?

          verbs_found.uniq.each do |verb|
            endpoint = Endpoint.new(mount_path, verb)
            endpoint.details = Details.new(PathInfo.new(path, idx + 1))

            extract_webrick_params(handler_body, verb).each do |param|
              endpoint.push_param(param)
            end

            if include_callee && !handler_body.empty?
              callees = Noir::RubyCalleeExtractor.callees_for_body(handler_body, path, handler_start_line)
              attach_ruby_callees(endpoint, callees)
            end

            @result << endpoint
          end
          next
        end

        # mount "PATH", ServletClass [, *opts]
        # Support mount ".." , Cls   and mount("..", Cls)
        if m = stripped.match(/\.mount\s*\(?\s*['"]([^'"]+)['"]\s*,\s*([A-Z][A-Za-z0-9_:]*)/)
          raw_path = m[1]
          mount_path = normalize_webrick_path(raw_path)
          cls_ref = m[2]
          cls = cls_ref.to_s.split("::").last

          # Skip static / internal handlers
          next if cls.includes?("FileHandler") || cls.includes?("DefaultFileHandler") || cls.includes?("ProcHandler") || cls.includes?("CGIHandler")

          if servlets = servlet_index[cls]?
            servlets.each do |do_name, info|
              verb = SERVLET_METHODS[do_name]? || "GET"
              endpoint = Endpoint.new(mount_path, verb)
              endpoint.details = Details.new(PathInfo.new(path, idx + 1))

              extract_webrick_params(info[:body], verb).each do |param|
                endpoint.push_param(param)
              end

              # Callee support for servlets is lower priority (no do-block); skip in v1 to keep extraction simple + low risk.
              # If include_callee, a future improvement can extract the def body precisely.

              @result << endpoint
            end
          end
        end
      end
    end

    private def normalize_webrick_path(p : String) : String
      # Support "#{VAR}/foo" -> "{VAR}/foo" like other ruby analyzers
      np = p.gsub(/\#\{([^}]+)\}/) { |_| "{#{$~[1].strip}}" }
      np = "/" + np unless np.starts_with?("/")
      np = np[0...-1] if np.ends_with?("/") && np != "/"
      np.empty? ? "/" : np
    end

    private def extract_verbs_from_handler_body(body : String) : Array(String)
      verbs = [] of String
      # Lower for simple includes; we re-upcase on output
      b = body.downcase
      has_method_check = b.includes?("request_method")

      ["get", "post", "put", "patch", "delete", "head", "options"].each do |v|
        if has_method_check
          if b.includes?("\"#{v}\"") || b.includes?("'#{v}'") || b.includes?(v.upcase) || b.includes?(":#{v}")
            verbs << v.upcase
          end
        end
      end
      # If the block is unconditional (plain mount_proc without method guard), verbs will be empty -> caller defaults to GET
      verbs.uniq
    end

    private def extract_webrick_params(body : String, verb : String) : Array(Param)
      return [] of Param if body.empty?
      params = [] of Param
      seen = Set(String).new

      # Work on comment-stripped form (preserve strings so "keys" stay).
      # MUST strip per-line then join: the strip_comment impl stops at first # across the entire input string.
      clean = body.lines.map { |l| Noir::RubyCalleeExtractor.strip_comment(l, preserve_strings: true) }.join("\n")

      # query: req.query['name'] or request.query["name"]
      clean.scan(/(?:req|request)\.query\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
        name = m[1].strip
        next if name.empty? || seen.includes?("query:#{name}")
        params << Param.new(name, "", "query")
        seen << "query:#{name}"
      end

      # header via req['X-Foo'] or req["x-foo"] (common) or req.header['x']
      clean.scan(/(?:req|request)\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
        name = m[1].strip
        next if name.empty? || seen.includes?("header:#{name}")
        params << Param.new(name, "", "header")
        seen << "header:#{name}"
      end
      clean.scan(/(?:req|request)\.header\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
        name = m[1].strip
        next if name.empty? || seen.includes?("header:#{name}")
        params << Param.new(name, "", "header")
        seen << "header:#{name}"
      end

      # cookies: req.cookies.find { |c| c.name == 'session' } or similar literal near cookies
      # Use line-scoped to avoid cross-line greedy match.
      clean.each_line do |ln|
        next unless ln.includes?("cookies") || ln.includes?(".name")
        ln.scan(/(?:req|request)\.cookies[^\n]*['"]([^'"]+)['"]/) do |m|
          name = m[1].strip
          next if name.empty? || seen.includes?("cookie:#{name}")
          params << Param.new(name, "", "cookie")
          seen << "cookie:#{name}"
        end
        ln.scan(/\.name\s*==\s*['"]([^'"]+)['"]/) do |m|
          name = m[1].strip
          next if name.empty? || seen.includes?("cookie:#{name}")
          params << Param.new(name, "", "cookie")
          seen << "cookie:#{name}"
        end
      end

      # body params for mutating methods (parse_query on body is the WEBrick idiom)
      if ["POST", "PUT", "PATCH"].includes?(verb)
        # direct: parse_query( req.body ) [ 'k' ] or .get  (allow optional Foo::Bar. prefix)
        clean.scan(/(?:[A-Za-z0-9_:.]+)?parse_query\s*\([^)]*(?:\.body|req\.body|request\.body|body)[^)]*\)\s*\[\s*['"]([^'"]+)['"]/) do |m|
          name = m[1].strip
          next if name.empty? || seen.includes?("form:#{name}")
          params << Param.new(name, "", "form")
          seen << "form:#{name}"
        end

        # assigned: p = [Prefix.]parse_query(req.body); p['k']
        form_vars = [] of String
        clean.scan(/([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:[A-Za-z0-9_:.]+)?parse_query\s*\([^)]*(?:body|req|request)[^)]*\)/) do |m|
          form_vars << m[1] unless form_vars.includes?(m[1])
        end
        form_vars.each do |var|
          clean.scan(/#{Regex.escape(var)}\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |mm|
            name = mm[1].strip
            next if name.empty? || seen.includes?("form:#{name}")
            params << Param.new(name, "", "form")
            seen << "form:#{name}"
          end
        end

        # json on body (allow JSON:: or prefix.)
        json_vars = [] of String
        clean.scan(/([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:[A-Za-z0-9_:.]+)?(JSON|json)\.parse\s*\([^)]*(?:body|req|request)[^)]*\)/) do |m|
          json_vars << m[1] unless json_vars.includes?(m[1])
        end
        json_vars.each do |var|
          clean.scan(/#{Regex.escape(var)}\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |mm|
            name = mm[1].strip
            next if name.empty? || seen.includes?("json:#{name}")
            params << Param.new(name, "", "json")
            seen << "json:#{name}"
          end
        end
        # direct (prefix.)json.parse(...)['k']
        clean.scan(/(?:[A-Za-z0-9_:.]+)?(JSON|json)\.parse\s*\([^)]*(?:body|req|request)[^)]*\)\s*\[\s*['"]([^'"]+)['"]/) do |m|
          name = m[2]? || m[1]?
          next if name.nil? || name.empty? || seen.includes?("json:#{name}")
          params << Param.new(name, "", "json")
          seen << "json:#{name}"
        end
      end

      params
    end
  end
end
