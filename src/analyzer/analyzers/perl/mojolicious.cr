require "../../engines/perl_engine"
require "../../../miniparsers/perl_callee_extractor"

module Analyzer::Perl
  class Mojolicious < PerlEngine
    HTTP_VERBS         = %w[get post put delete patch options head]
    LITE_VERB_RE       = /^\s*(get|post|put|patch|delete|del|options|head|websocket)\s+['"]([^'"]+)['"]/
    LITE_ANY_RE        = /^\s*any\s+(?:\[([^\]]+)\]\s*=>\s*)?['"]([^'"]+)['"]/
    FULL_VERB_RE       = /->\s*(get|post|put|patch|delete|del|options|head|websocket)\s*\(\s*['"]([^'"]+)['"]/
    FULL_ANY_RE        = /->\s*any\s*\(\s*(?:\[([^\]]+)\]\s*,?\s*=?>?\s*)?['"]([^'"]+)['"]/
    FULL_ROUTE_RE      = /->\s*route\s*\(\s*['"]([^'"]+)['"]\s*\)(?:\s*->\s*via\s*\(\s*([^)]+)\))?/
    PREFIX_SEGMENT_RE  = /->\s*(?:under|any|route)\s*\(\s*(?:\[[^\]]+\]\s*,?\s*=?>?\s*)?['"]([^'"]+)['"]/
    ASSIGNMENT_HEAD_RE = /^\s*(?:my|our|local)?\s*\$([A-Za-z_]\w*)\s*=\s*(.+)$/
    CHAIN_RECEIVER_RE  = /\$([A-Za-z_]\w*)\s*->/
    PRELUDE_VAR_RE     = /\$([A-Za-z_]\w*)/

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      controller_callees = include_callee ? index_controller_callees : {} of String => Array(Noir::PerlCalleeExtractor::Entry)

      parallel_file_scan do |path|
        result.concat(analyze_file(path, include_callee, controller_callees))
      end
      result
    end

    def analyze_file(path : String) : Array(Endpoint)
      analyze_file(path, any_to_bool(@options["include_callee"]?), {} of String => Array(Noir::PerlCalleeExtractor::Entry))
    end

    private def analyze_file(path : String,
                             include_callee : Bool,
                             controller_callees : Hash(String, Array(Noir::PerlCalleeExtractor::Entry))) : Array(Endpoint)
      ext = File.extname(path)
      return [] of Endpoint unless ext == ".pl" || ext == ".pm" ||
                                   ext == ".psgi" || ext == ".t"
      # Skip standard Perl test conventions: anything under `/t/`
      # (CPAN convention for test scripts) or with a `.t` filename
      # (which is also a test script — accepted above so analyzers
      # *could* opt in, but Mojolicious's own `t/mojolicious/*.t`
      # accounts for ~1100 phantom endpoints).
      return [] of Endpoint if perl_test_path?(path, ext)

      endpoints = [] of Endpoint
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end
        endpoints.concat(analyze_content(content, path, include_callee, controller_callees))
      end
      endpoints
    end

    private def perl_test_path?(path : String, ext : String) : Bool
      return true if ext == ".t"
      return true if path.includes?("/t/")
      false
    end

    def analyze_content(content : String,
                        file_path : String,
                        include_callee : Bool = false,
                        controller_callees : Hash(String, Array(Noir::PerlCalleeExtractor::Entry)) = {} of String => Array(Noir::PerlCalleeExtractor::Entry)) : Array(Endpoint)
      endpoints = [] of Endpoint
      raw_lines = content.lines
      sanitized_lines = sanitize_perl_lines(raw_lines)
      offsets = line_offsets(content)
      last_endpoint : Endpoint? = nil
      var_prefix = {} of String => String

      sanitized_lines.each_with_index do |line, index|
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?('#')

        update_var_prefix(line, var_prefix)

        line_endpoints = line_to_endpoints(line, var_prefix)
        line_endpoints.each do |endpoint|
          endpoint.details = Details.new(PathInfo.new(file_path, index + 1))
          extract_path_params(endpoint).each { |p| push_unique_param(endpoint, p) }
          attach_route_callees(endpoint, content, raw_lines[index], offsets[index], controller_callees) if include_callee
          endpoints << endpoint
        end

        targets = if line_endpoints.empty?
                    if le = last_endpoint
                      [le]
                    else
                      [] of Endpoint
                    end
                  else
                    line_endpoints
                  end

        targets.each do |target|
          extract_params_from_line(line, target.method).each do |param|
            push_unique_param(target, param)
          end
        end

        last_endpoint = line_endpoints.last unless line_endpoints.empty?
      end

      endpoints
    end

    # POD blocks (`=head1` ... `=cut`) and `__END__`/`__DATA__` sections
    # are documentation/data, not code. Real-world Mojolicious modules
    # (e.g. `Mojolicious::Plugin::Minion::Admin`) ship example
    # `app->routes->any('/...')` calls inside their POD, which would
    # otherwise be picked up as live routes. We blank those lines while
    # preserving the original line count so endpoint line numbers stay
    # aligned with the source file.
    private def sanitize_perl_lines(lines : Array(String)) : Array(String)
      in_pod = false
      ended = false
      lines.map do |line|
        stripped = line.lstrip
        if ended
          ""
        elsif stripped.starts_with?("__END__") || stripped.starts_with?("__DATA__")
          ended = true
          ""
        elsif in_pod
          if stripped.starts_with?("=cut")
            in_pod = false
          end
          ""
        elsif stripped.size >= 2 && stripped[0] == '=' && stripped[1].ascii_letter?
          # POD directives: =head1, =head2, =item, =over, =pod, =for, =begin, =encoding ...
          in_pod = true
          ""
        else
          line
        end
      end
    end

    private def index_controller_callees : Hash(String, Array(Noir::PerlCalleeExtractor::Entry))
      callees = {} of String => Array(Noir::PerlCalleeExtractor::Entry)

      all_files.each do |path|
        next if File.directory?(path)
        ext = File.extname(path)
        next unless ext == ".pl" || ext == ".pm" || ext == ".psgi" || ext == ".t"

        content = read_file_content(path)
        Noir::PerlCalleeExtractor.controller_action_callees(content, path).each do |key, entries|
          callees[key] ||= entries
        end
      end

      callees
    end

    def line_to_endpoints(line : String) : Array(Endpoint)
      line_to_endpoints(line, {} of String => String)
    end

    def line_to_endpoints(line : String, var_prefix : Hash(String, String)) : Array(Endpoint)
      result = [] of Endpoint

      # Mojolicious::Lite: `get '/path' => ...`
      if m = line.match(LITE_VERB_RE)
        url = m[2]
        result << build_endpoint(url, m[1]) unless disallowed_route_url?(url)
      end

      # Mojolicious::Lite: `any '/path'` or `any [GET => 'POST'] => '/path'`
      if m = line.match(LITE_ANY_RE)
        url = m[2]
        unless disallowed_route_url?(url)
          methods_str = m[1]?
          methods_for_any(methods_str).each do |verb|
            result << Endpoint.new(url, verb)
          end
        end
      end

      # Full app: `$r->get('/path')` etc.
      if m = line.match(FULL_VERB_RE)
        leaf = m[2]
        unless disallowed_route_url?(leaf)
          prefix = compute_chain_prefix(line, m.begin(0) || 0, var_prefix)
          result << build_endpoint(join_url(prefix, leaf), m[1])
        end
      end

      # Full app: `$r->any(['GET','POST'] => '/path')` or `$r->any('/path')`
      if m = line.match(FULL_ANY_RE)
        leaf = m[2]
        unless disallowed_route_url?(leaf)
          methods_str = m[1]?
          prefix = compute_chain_prefix(line, m.begin(0) || 0, var_prefix)
          full = join_url(prefix, leaf)
          methods_for_any(methods_str).each do |verb|
            result << Endpoint.new(full, verb)
          end
        end
      end

      # Full app: `$r->route('/path')->via('GET')` or `via(qw(GET POST))`
      if m = line.match(FULL_ROUTE_RE)
        leaf = m[1]
        unless disallowed_route_url?(leaf)
          via_str = m[2]?
          prefix = compute_chain_prefix(line, m.begin(0) || 0, var_prefix)
          full = join_url(prefix, leaf)
          if via_str
            methods_from_via(via_str).each do |verb|
              result << Endpoint.new(full, verb)
            end
          else
            # `route` without `via` defaults to any method; treat as GET
            result << Endpoint.new(full, "GET")
          end
        end
      end

      result
    end

    # `$ua->get('http://example.com/foo')` is a `Mojo::UserAgent` HTTP
    # client call, not a route — and `Mojolicious::Lite`'s `get '/foo'`
    # never names a fully-qualified URL with a scheme. Skip any route
    # whose declared path contains `://` to suppress these UA-call FPs.
    private def disallowed_route_url?(url : String) : Bool
      url.includes?("://")
    end

    # Record `my $V = ANYTHING->{under,any,route}('/PREFIX' ...)` so
    # subsequent calls like `$V->get('/leaf')` resolve to
    # `/PREFIX/leaf`. Real-world Mojolicious plugins (e.g.
    # `Mojolicious::Plugin::Minion::Admin`) lean heavily on this
    # pattern — without it the admin endpoints all look like
    # top-level `/stats`, `/jobs`, etc. instead of `/minion/stats`.
    private def update_var_prefix(line : String, var_prefix : Hash(String, String))
      return unless m = line.match(ASSIGNMENT_HEAD_RE)
      var = m[1]
      rhs = m[2]

      segments = [] of String
      rhs.scan(PREFIX_SEGMENT_RE) do |seg_match|
        segments << seg_match[1]
      end
      return if segments.empty?

      receiver_prefix = ""
      if rm = rhs.match(CHAIN_RECEIVER_RE)
        if existing = var_prefix[rm[1]]?
          receiver_prefix = existing
        end
      end

      combined = segments.reduce(receiver_prefix) { |acc, seg| join_url(acc, seg) }
      var_prefix[var] = combined unless combined.empty?
    end

    # Compute the URL prefix to prepend to a leaf route appearing at
    # `leaf_start` on `line`. Considers two sources:
    #   * Inline chains — `$r->under('/a')->get('/leaf')` → `/a` prefix
    #     even when nothing is assigned to a variable.
    #   * Variable receiver — `$V->get('/leaf')` where `$V` was
    #     previously assigned a tracked prefix.
    private def compute_chain_prefix(line : String, leaf_start : Int32, var_prefix : Hash(String, String)) : String
      prelude = leaf_start > 0 ? line[0, leaf_start] : ""
      prefix = ""

      # Find the chain receiver: the `$var` token directly to the left of
      # the leaf call. In `$prefix->get('/x')` the prelude is `$prefix`;
      # in `$r->under('/a')->get('/x')` the prelude is `$r->under('/a')`.
      # The variable immediately preceding the leaf `->` is the last
      # `$var` token in the prelude — `$prefix` and `$r` respectively.
      last_var : String? = nil
      prelude.scan(PRELUDE_VAR_RE) { |m| last_var = m[1] }
      if name = last_var
        if vp = var_prefix[name]?
          prefix = vp
        end
      end

      prelude.scan(PREFIX_SEGMENT_RE) do |seg_match|
        prefix = join_url(prefix, seg_match[1])
      end

      prefix
    end

    private def join_url(prefix : String, leaf : String) : String
      return leaf if prefix.empty?
      return prefix if leaf.empty?

      base = prefix.size > 1 ? prefix.chomp('/') : prefix
      tail = leaf.starts_with?('/') ? leaf : "/#{leaf}"
      joined = "#{base}#{tail}"
      joined.size > 1 && joined.ends_with?('/') ? joined.rchop : joined
    end

    private def build_endpoint(path : String, verb : String) : Endpoint
      v = verb.downcase
      if v == "websocket"
        endpoint = Endpoint.new(path, "GET")
        endpoint.protocol = "ws"
        endpoint
      else
        v = "delete" if v == "del"
        Endpoint.new(path, v.upcase)
      end
    end

    private def normalize_method(verb : String) : String
      v = verb.downcase
      v = "delete" if v == "del"
      v.upcase
    end

    private def methods_for_any(methods_str : String?) : Array(String)
      return HTTP_VERBS.map(&.upcase) if methods_str.nil?
      methods_from_via(methods_str)
    end

    private def methods_from_via(spec : String) : Array(String)
      verbs = [] of String
      spec.scan(/['"]?([A-Za-z]+)['"]?/) do |m|
        verb = m[1].upcase
        next if verb == "QW"
        verbs << verb if HTTP_VERBS.includes?(verb.downcase)
      end
      verbs
    end

    private def extract_path_params(endpoint : Endpoint) : Array(Param)
      params = [] of Param
      endpoint.url.scan(/[:*#]([A-Za-z_][A-Za-z0-9_]*)/) do |m|
        params << Param.new(m[1], "", "path")
      end
      params
    end

    private def extract_params_from_line(line : String, method : String) : Array(Param)
      params = [] of Param

      line.scan(/->\s*req\s*->\s*query_params\s*->\s*param\s*\(\s*['"]([^'"]+)['"]/) do |m|
        params << Param.new(m[1], "", "query")
      end

      line.scan(/->\s*req\s*->\s*body_params\s*->\s*param\s*\(\s*['"]([^'"]+)['"]/) do |m|
        params << Param.new(m[1], "", "form")
      end

      line.scan(/->\s*req\s*->\s*headers\s*->\s*header\s*\(\s*['"]([^'"]+)['"]/) do |m|
        params << Param.new(m[1], "", "header")
      end

      line.scan(/->\s*(?:req\s*->\s*)?cookie\s*\(\s*['"]([^'"]+)['"]/) do |m|
        params << Param.new(m[1], "", "cookie")
      end

      line.scan(/->\s*param\s*\(\s*['"]([^'"]+)['"]/) do |m|
        param_type = (method == "GET" || method == "HEAD" || method == "OPTIONS") ? "query" : "form"
        params << Param.new(m[1], "", param_type)
      end

      params
    end

    private def push_unique_param(endpoint : Endpoint, param : Param)
      return if param.name.empty?
      endpoint.params.each do |existing|
        return if existing.name == param.name && existing.param_type == param.param_type
      end
      endpoint.push_param(param)
    end

    private def attach_route_callees(endpoint : Endpoint,
                                     content : String,
                                     line : String,
                                     line_offset : Int32,
                                     controller_callees : Hash(String, Array(Noir::PerlCalleeExtractor::Entry)))
      line_end = line_offset + line.size
      if body = Noir::PerlCalleeExtractor.extract_sub_after(content, line_offset, line_end)
        body_text, start_line = body
        Noir::PerlCalleeExtractor.attach_to(endpoint, Noir::PerlCalleeExtractor.callees_for_body(body_text, endpoint.details.code_paths.first.path, start_line))
        return
      end

      if target = controller_action_target(line)
        if callees = controller_callees[target]?
          Noir::PerlCalleeExtractor.attach_to(endpoint, callees)
        end
      end
    end

    private def controller_action_target(line : String) : String?
      if match = line.match(/->\s*to\s*\(\s*['"]([A-Za-z_][A-Za-z0-9_:\/-]*)#([A-Za-z_][A-Za-z0-9_]*)['"]\s*\)/)
        return "#{controller_key(match[1])}##{match[2]}"
      end

      if match = line.match(/->\s*to\s*\(([^)]*)\)/)
        args = match[1]
        controller = named_to_arg(args, "controller")
        action = named_to_arg(args, "action")
        "#{controller_key(controller)}##{action}" if controller && action
      end
    end

    private def named_to_arg(args : String, name : String) : String?
      if match = args.match(/(?:^|[,\s])#{name}\s*=>\s*['"]([A-Za-z_][A-Za-z0-9_:\/-]*)['"]/)
        match[1]
      end
    end

    private def controller_key(controller : String) : String
      controller.gsub("::", "/").split('/').reject(&.empty?).map do |segment|
        underscore(segment.gsub("-", "_"))
      end.join("/")
    end

    private def underscore(name : String) : String
      name.gsub(/([a-z0-9])([A-Z])/, "\\1_\\2").downcase
    end

    private def line_offsets(content : String) : Array(Int32)
      offsets = [0]
      content.each_char_with_index do |char, index|
        offsets << index + 1 if char == '\n'
      end
      offsets
    end
  end
end
