require "../../engines/specification_engine"

module Analyzer::Specification
  class Caddy < SpecificationEngine
    analyzer_for "caddy"

    METHOD_ANY = "ANY"

    HANDLE_OPEN_RE   = /^handle(_path)?\s+(\S+)\s*\{?/
    ROUTE_OPEN_RE    = /^route\s+(\S+)\s*\{?/
    REDIR_RE         = /^redir\s+(\S+)\s+(\S+)/
    RESPOND_RE       = /^respond\s+(\S+)/
    NAMED_MATCH_OPEN = /^(@[A-Za-z_]\w*)\s*\{?/
    METHOD_RE        = /^method\s+(.+)/
    PATH_RE          = /^path\s+(.+)/
    HANDLE_REF_RE    = /^(?:handle(?:_path)?|route)\s+(@[A-Za-z_]\w*)\s*\{?/
    SITE_BLOCK_RE    = /^([A-Za-z0-9_.:\/@*?-]+(?:\s*,\s*[A-Za-z0-9_.:\/@*?-]+)*)\s*\{$/
    # `reverse_proxy /api/* localhost:9001`: any directive's first argument
    # may be its matcher token.
    DIRECTIVE_RE = /^([a-z_][a-z0-9_]*)\s+(\S+)(\s+\S)?/
    # Directives whose first argument is a file or a name, never a matcher.
    NON_MATCHER_DIRECTIVES = %w[import tls bind log fs handle_errors]

    def analyze
      each_spec_file_with_details(Noir::LocatorKeys::CADDY_SPEC) do |path, details|
        content = read_file_content(path)
        if path.ends_with?(".json")
          process_json(content, details)
        else
          process_caddyfile(content, path, details)
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
      # Depths whose lines are directives of a site or of a `handle` /
      # `route` block. A directive's own sub-block (`file_server { root
      # /srv }`) holds sub-directives, not matchers.
      routing_depths = [] of Int32

      lines.each_with_index do |raw, idx|
        line = strip_comment(raw).strip
        next if line.empty?
        line_no = idx + 1
        while (top = routing_depths.last?) && depth < top
          routing_depths.pop
        end
        routing = routing_depths.last? == depth

        # Site address line is only meaningful at the file root.
        if depth == 0
          if sm = SITE_BLOCK_RE.match(line)
            site_hosts = sm[1].split(/\s*,\s*/).reject(&.empty?)
            depth += brace_delta(line)
            routing_depths << depth if depth > 0
            next
          end
        end

        if m = NAMED_MATCH_OPEN.match(line)
          name = m[1]
          matchers[name] ||= NamedMatcher.new
          rest = line[m.end..].strip
          if rest.empty? || rest == "{"
            current_matcher = name
            matcher_depth = depth + 1
          else
            # `@ws path /ws /socket/*`: the one-line form.
            add_matcher_condition(matchers[name], rest.lchop('{').rchop('}').strip)
          end
          depth += brace_delta(line)
          next
        end

        if active_matcher = current_matcher
          if add_matcher_condition(matchers[active_matcher], line)
            depth += brace_delta(line)
            current_matcher = nil if depth < matcher_depth
            next
          end
        end

        if m = HANDLE_REF_RE.match(line)
          emit_matcher_ref(matchers[m[1]]?, "handle", site_hosts, source_path, line_no)
          depth += brace_delta(line)
          routing_depths << depth if routing && !line.starts_with?("handle_path") && brace_delta(line) > 0
          next
        end

        if m = HANDLE_OPEN_RE.match(line)
          kind = m[1]? == "_path" ? "handle_path" : "handle"
          emit_endpoint(m[2], METHOD_ANY, kind, site_hosts, source_path, line_no) if path_matcher?(m[2])
          depth += brace_delta(line)
          # `handle_path` strips its prefix, so a matcher inside it is not the
          # request path.
          routing_depths << depth if routing && kind == "handle" && brace_delta(line) > 0
          next
        end

        if m = ROUTE_OPEN_RE.match(line)
          emit_endpoint(m[1], METHOD_ANY, "route", site_hosts, source_path, line_no) if path_matcher?(m[1])
          depth += brace_delta(line)
          routing_depths << depth if routing && brace_delta(line) > 0
          next
        end

        if m = REDIR_RE.match(line)
          # `redir [<matcher>] <to> [<code>]`. Without a matcher the first
          # argument is the *destination* — `redir https://example.com{uri}
          # permanent` describes where traffic goes, not a route this server
          # serves, so emitting it produced a phantom absolute-URL endpoint.
          emit_endpoint(m[1], METHOD_ANY, "redir", site_hosts, source_path, line_no, target: m[2]) if path_matcher?(m[1])
          depth += brace_delta(line)
          next
        end

        if m = RESPOND_RE.match(line)
          # `respond [<matcher>] <status>|<body>`. Only a matcher token names a
          # route; the far more common `respond "Hello, world!"` / `respond 404`
          # forms carry a body or status and used to surface as `/"Hello,`.
          emit_endpoint(m[1], METHOD_ANY, "respond", site_hosts, source_path, line_no) if path_matcher?(m[1])
          depth += brace_delta(line)
          next
        end

        if routing && (m = DIRECTIVE_RE.match(line)) && !NON_MATCHER_DIRECTIVES.includes?(m[1])
          token = m[2]
          if token.starts_with?('@')
            emit_matcher_ref(matchers[token]?, m[1], site_hosts, source_path, line_no)
          elsif token.starts_with?('/') && m[3]?
            # A lone `/path` argument (`root /srv`) is the directive's value.
            emit_endpoint(token, METHOD_ANY, m[1], site_hosts, source_path, line_no)
          end
        end

        depth += brace_delta(line)
        current_matcher = nil if current_matcher && depth < matcher_depth
        if depth <= 0
          depth = 0
          site_hosts = [] of String
        end
      end
    end

    # `method GET POST` / `path /a /b/*` inside a named matcher.
    private def add_matcher_condition(matcher : NamedMatcher, text : String) : Bool
      if mm = METHOD_RE.match(text)
        mm[1].split(/\s+/).reject(&.empty?).each { |x| matcher.methods << x.upcase }
      elsif pm = PATH_RE.match(text)
        pm[1].split(/\s+/).reject(&.empty?).each { |x| matcher.paths << x }
      else
        return false
      end
      true
    end

    private def emit_matcher_ref(matcher : NamedMatcher?, origin : String, hosts : Array(String), source_path : String, line : Int32)
      return unless matcher
      methods = matcher.methods.empty? ? [METHOD_ANY] : matcher.methods
      matcher.paths.each do |p|
        methods.each { |method| emit_endpoint(p, method, origin, hosts, source_path, line) }
      end
    end

    # An inline Caddyfile matcher token is `*`, or a path starting with `/`
    # (a named `@matcher` is handled separately by `HANDLE_REF_RE`). Anything
    # else in that argument position is a body, a destination, a status code
    # or the block's opening brace — `handle {` used to emit `/{`.
    private def path_matcher?(token : String) : Bool
      token == "*" || token.starts_with?('/')
    end

    # Net brace movement for the line. A bare `{` opens (+1), a bare
    # `}` closes (-1); pairs on the same line cancel out so callers
    # don't have to special-case single-line blocks like
    # `basic_auth { admin $2y$... }`.
    private def brace_delta(line : String) : Int32
      line.count('{') - line.count('}')
    end

    # ----------- JSON -----------

    private def process_json(content : String, details : Details)
      doc = parse_json_lenient(content)
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
