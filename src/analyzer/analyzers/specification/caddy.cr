require "../../../models/analyzer"

module Analyzer::Specification
  class Caddy < Analyzer
    METHOD_ANY = "ANY"

    HANDLE_OPEN_RE   = /^handle(_path)?\s+(\S+)\s*\{?/
    ROUTE_OPEN_RE    = /^route\s+(\S+)\s*\{?/
    REDIR_RE         = /^redir\s+(\S+)\s+(\S+)/
    RESPOND_RE       = /^respond\s+(\S+)/
    NAMED_MATCH_OPEN = /^(@[A-Za-z_]\w*)\s*\{?/
    METHOD_RE        = /^method\s+(.+)/
    PATH_RE          = /^path\s+(.+)/
    HANDLE_REF_RE    = /^handle\s+(@[A-Za-z_]\w*)\s*\{?/
    SITE_BLOCK_RE    = /^([A-Za-z0-9_.:\/@*?-]+(?:\s*,\s*[A-Za-z0-9_.:\/@*?-]+)*)\s*\{$/

    def analyze
      spec_files = CodeLocator.instance.all("caddy-spec")
      return @result unless spec_files.is_a?(Array(String))

      spec_files.each do |path|
        next unless File.exists?(path)

        details = Details.new(PathInfo.new(path))
        content = read_file_content(path)
        begin
          if path.ends_with?(".json")
            process_json(content, details)
          else
            process_caddyfile(content, path, details)
          end
        rescue e
          @logger.debug "Exception processing #{path}"
          @logger.debug_sub e
        end
      end

      @result
    end

    # ----------- Caddyfile -----------

    private record NamedMatcher, methods : Array(String) = [] of String, paths : Array(String) = [] of String

    private def process_caddyfile(content : String, source_path : String, details : Details)
      lines = content.lines
      site_hosts = [] of String
      matchers = {} of String => NamedMatcher
      current_matcher : String? = nil
      depth = 0
      matcher_depth = -1

      lines.each_with_index do |raw, idx|
        line = strip_comment(raw).strip
        next if line.empty?
        line_no = idx + 1

        # Site address line is only meaningful at the file root.
        if depth == 0
          if sm = SITE_BLOCK_RE.match(line)
            site_hosts = sm[1].split(/\s*,\s*/).reject(&.empty?)
            depth += brace_delta(line)
            next
          end
        end

        if m = NAMED_MATCH_OPEN.match(line)
          name = m[1]
          matchers[name] ||= NamedMatcher.new
          current_matcher = name
          matcher_depth = depth + 1
          depth += brace_delta(line)
          next
        end

        if active_matcher = current_matcher
          if mm = METHOD_RE.match(line)
            mm[1].split(/\s+/).reject(&.empty?).each { |x| matchers[active_matcher].methods << x.upcase }
            depth += brace_delta(line)
            current_matcher = nil if depth < matcher_depth
            next
          end
          if pm = PATH_RE.match(line)
            pm[1].split(/\s+/).reject(&.empty?).each { |x| matchers[active_matcher].paths << x }
            depth += brace_delta(line)
            current_matcher = nil if depth < matcher_depth
            next
          end
        end

        if m = HANDLE_REF_RE.match(line)
          matcher = matchers[m[1]]?
          if matcher && !matcher.paths.empty?
            methods = matcher.methods.empty? ? [METHOD_ANY] : matcher.methods
            matcher.paths.each do |p|
              methods.each { |method| emit_endpoint(p, method, "handle", site_hosts, source_path, line_no) }
            end
          end
          depth += brace_delta(line)
          next
        end

        if m = HANDLE_OPEN_RE.match(line)
          kind = m[1]? == "_path" ? "handle_path" : "handle"
          emit_endpoint(m[2], METHOD_ANY, kind, site_hosts, source_path, line_no)
          depth += brace_delta(line)
          next
        end

        if m = ROUTE_OPEN_RE.match(line)
          emit_endpoint(m[1], METHOD_ANY, "route", site_hosts, source_path, line_no)
          depth += brace_delta(line)
          next
        end

        if m = REDIR_RE.match(line)
          emit_endpoint(m[1], METHOD_ANY, "redir", site_hosts, source_path, line_no, target: m[2])
          depth += brace_delta(line)
          next
        end

        if m = RESPOND_RE.match(line)
          target = m[1]
          # `respond` may be invoked with a status code (no path). Skip
          # bare-status forms so we don't surface "200" as a URL.
          unless target.matches?(/\A\d+\z/)
            emit_endpoint(target, METHOD_ANY, "respond", site_hosts, source_path, line_no)
          end
          depth += brace_delta(line)
          next
        end

        depth += brace_delta(line)
        current_matcher = nil if current_matcher && depth < matcher_depth
        if depth <= 0
          depth = 0
          site_hosts = [] of String
        end
      end
    end

    # Net brace movement for the line. A bare `{` opens (+1), a bare
    # `}` closes (-1); pairs on the same line cancel out so callers
    # don't have to special-case single-line blocks like
    # `basic_auth { admin $2y$... }`.
    private def brace_delta(line : String) : Int32
      opens = 0
      closes = 0
      line.each_char do |ch|
        case ch
        when '{' then opens += 1
        when '}' then closes += 1
        end
      end
      opens - closes
    end

    # ----------- JSON -----------

    private def process_json(content : String, details : Details)
      doc = JSON.parse(content)
      apps = doc["apps"]?.try(&.as_h?)
      return unless apps
      http = apps["http"]?.try(&.as_h?)
      return unless http
      servers = http["servers"]?.try(&.as_h?)
      return unless servers

      servers.each_value do |server|
        server_h = server.as_h?
        next unless server_h
        routes = server_h["routes"]?.try(&.as_a?) || [] of JSON::Any
        process_json_routes(routes, details)
      end
    end

    private def process_json_routes(routes : Array(JSON::Any), details : Details, parent_hosts : Array(String) = [] of String)
      routes.each do |route|
        h = route.as_h?
        next unless h
        matches = h["match"]?.try(&.as_a?) || [] of JSON::Any
        matches.each { |match| process_json_match(match, details, parent_hosts) }
        sub_routes = h["routes"]?.try(&.as_a?)
        process_json_routes(sub_routes, details, parent_hosts) if sub_routes
      end
    end

    private def process_json_match(match : JSON::Any, details : Details, parent_hosts : Array(String))
      h = match.as_h?
      return unless h

      hosts = collect_strings(h["host"]?)
      hosts = parent_hosts if hosts.empty?

      paths = collect_strings(h["path"]?)
      methods = collect_strings(h["method"]?).map(&.upcase)
      methods = [METHOD_ANY] if methods.empty?

      paths.each do |path|
        methods.each do |method|
          emit_endpoint(path, method, "json", hosts, details.code_paths.first.path, 0)
        end
      end
    end

    private def collect_strings(node : JSON::Any?) : Array(String)
      out_strings = [] of String
      return out_strings if node.nil?
      if arr = node.as_a?
        arr.each do |entry|
          if str = entry.as_s?
            out_strings << str unless str.empty?
          end
        end
      elsif str = node.as_s?
        out_strings << str unless str.empty?
      end
      out_strings
    end

    private def strip_comment(line : String) : String
      idx = line.index('#')
      idx.nil? ? line : line[0...idx]
    end

    private def emit_endpoint(path : String, method : String, origin : String, hosts : Array(String), source_path : String, line : Int32, target : String? = nil)
      return if path.empty?
      detail = if line > 0
                 Details.new(PathInfo.new(source_path, line))
               else
                 Details.new(PathInfo.new(source_path))
               end
      use_hosts = hosts.empty? ? [""] : hosts
      use_hosts.each do |host|
        endpoint = Endpoint.new(path, method, detail)
        endpoint.add_tag(Tag.new("caddy-source", origin, "caddy_analyzer"))
        endpoint.add_tag(Tag.new("caddy-host", host, "caddy_analyzer")) unless host.empty?
        endpoint.add_tag(Tag.new("caddy-redirect-target", target, "caddy_analyzer")) if target && !target.empty?
        @result << endpoint
      end
    end
  end
end
