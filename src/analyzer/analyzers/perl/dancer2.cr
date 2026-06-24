require "../../engines/perl_engine"
require "../../../miniparsers/perl_callee_extractor"

module Analyzer::Perl
  # Dancer2 route DSL analyzer.
  #
  # Dancer2 (https://github.com/PerlDancer/Dancer2) exposes routes through
  # a keyword DSL exported by `use Dancer2`:
  #
  #   get  '/'            => sub { ... };
  #   post '/users'       => sub { ... };
  #   del  '/users/:id'   => sub { ... };   # `del`, not `delete`
  #   any  ['get','post'] => '/feed' => sub { ... };
  #   any  '/all'         => sub { ... };   # every HTTP verb
  #
  #   prefix '/api' => sub {                 # block-scoped prefix
  #     get '/status' => sub { ... };        # => /api/status
  #   };
  #   prefix '/v2';                          # procedural prefix
  #   get '/ping' => sub { ... };            # => /v2/ping
  #
  # Route paths support named placeholders (`:id`, with optional type
  # constraints `:id[Int]`), splat (`*`) / megasplat (`**`) wildcards, and
  # regex routes (`qr{...}`). Handlers read input through the modern
  # accessors (`route_parameters`, `query_parameters`, `body_parameters`,
  # `cookies`, `request->header`, `upload`) as well as the legacy
  # `param`/`params` helpers.
  class Dancer2 < PerlEngine
    # Verb spellings accepted inside an `any [...]` method list. Dancer2
    # normalizes `del` to `delete` and registers HEAD alongside GET, so the
    # arrayref form takes both the route-keyword spelling (`del`) and the
    # HTTP-method spelling (`delete`, `head`).
    ANY_LIST_VERBS = %w[get head post put del delete patch options]
    ANY_METHODS    = %w[GET POST PUT DELETE PATCH OPTIONS HEAD]

    VERB_STRING_RE  = /^\s*(get|post|put|patch|options|del)\s+(['"])([^'"]*)\2/
    VERB_QR_RE      = /^\s*(get|post|put|patch|options|del)\s+qr\s*(?:\{([^}]*)\}|\/((?:[^\/\\]|\\.)*)\/|!([^!]*)!|#([^#]*)#|\(([^)]*)\))/
    ANY_LIST_RE     = /^\s*any\s*\[([^\]]*)\]\s*=>\s*(['"])([^'"]*)\2/
    ANY_BARE_RE     = /^\s*any\s+(['"])([^'"]*)\1/
    PREFIX_BLOCK_RE = /^\s*prefix\s+(['"])([^'"]*)\1\s*=>\s*sub\b/
    PREFIX_RESET_RE = /^\s*prefix\s+(?:undef|''|""|'\/'|"\/")\s*;/
    PREFIX_PROC_RE  = /^\s*prefix\s+(['"])([^'"]*)\1\s*;/
    CODEREF_RE      = /=>\s*\\&\s*([A-Za-z_]\w*)/

    private struct RouteHit
      property url, methods, line_index, char_offset, handler_name

      def initialize(@url : String,
                     @methods : Array(String),
                     @line_index : Int32,
                     @char_offset : Int32,
                     @handler_name : String?)
      end
    end

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      parallel_file_scan do |path|
        result.concat(analyze_file(path, include_callee))
      end
      result
    end

    def analyze_file(path : String) : Array(Endpoint)
      analyze_file(path, any_to_bool(@options["include_callee"]?))
    end

    private def analyze_file(path : String, include_callee : Bool) : Array(Endpoint)
      ext = File.extname(path)
      return [] of Endpoint unless ext == ".pl" || ext == ".pm" ||
                                   ext == ".psgi" || ext == ".t"
      return [] of Endpoint if perl_test_path?(path, ext)

      content = read_file_content(path)
      analyze_content(content, path, include_callee)
    end

    def analyze_content(content : String, file_path : String) : Array(Endpoint)
      analyze_content(content, file_path, false)
    end

    def analyze_content(content : String, file_path : String, include_callee : Bool) : Array(Endpoint)
      raw_lines = content.lines
      pod_blanked = sanitize_perl_lines(raw_lines)
      code_lines = code_only_lines(pod_blanked)
      offsets = line_offsets(content)

      routes = collect_routes(pod_blanked, code_lines, offsets)
      return [] of Endpoint if routes.empty?

      decl_offsets = routes.map(&.char_offset)
      # Routes wired to a named sub via `=> \&handler` need the file's
      # named-sub bodies resolved so their params/callees are still
      # discovered. Inline-sub routes (the common case) don't, so only
      # pay for the index when a code-ref route is actually present.
      named_bodies = routes.any?(&.handler_name) ? Noir::PerlCalleeExtractor.named_sub_bodies(content, file_path) : nil

      endpoints = [] of Endpoint
      routes.each_with_index do |route, idx|
        search_limit = decl_offsets[idx + 1]? || content.size
        body = body_for_route(content, route, search_limit, named_bodies)

        path_params = extract_path_params(route.url)

        route.methods.each do |method|
          endpoint = Endpoint.new(route.url, method)
          endpoint.details = Details.new(PathInfo.new(file_path, route.line_index + 1))
          path_params.each { |param| push_unique_param(endpoint, param) }
          # Legacy `param`/`params` accessors bucket by HTTP method (query
          # vs form), so an `any` route's params must be resolved per
          # generated method rather than once for the first method.
          if body
            extract_params_from_body(body[0], method).each { |param| push_unique_param(endpoint, param) }
          end

          if include_callee && body
            Noir::PerlCalleeExtractor.attach_to(
              endpoint,
              Noir::PerlCalleeExtractor.callees_for_body(body[0], file_path, body[1])
            )
          end

          endpoints << endpoint
        end
      end

      endpoints
    end

    # Walk the file tracking brace depth so block-scoped `prefix` calls
    # propagate to the routes nested inside them, while procedural
    # `prefix '/x';` declarations set a running top-level prefix.
    private def collect_routes(pod_blanked : Array(String),
                               code_lines : Array(String),
                               offsets : Array(Int32)) : Array(RouteHit)
      routes = [] of RouteHit
      prefix_stack = [] of Tuple(Int32, String)
      proc_prefix = ""
      depth = 0

      pod_blanked.each_with_index do |line, index|
        stripped = line.strip
        unless stripped.empty? || stripped.starts_with?('#')
          if block = line.match(PREFIX_BLOCK_RE)
            prefix_stack << {depth, normalize_prefix(block[2])}
          elsif line.matches?(PREFIX_RESET_RE)
            proc_prefix = ""
          elsif (proc = line.match(PREFIX_PROC_RE)) && prefix_stack.empty?
            proc_prefix = normalize_prefix(proc[2])
          else
            line_to_routes(line, index, offsets[index], current_prefix(proc_prefix, prefix_stack)).each do |route|
              routes << route
            end
          end
        end

        depth += brace_delta(code_lines[index]? || "")
        while !prefix_stack.empty? && prefix_stack.last[0] >= depth
          prefix_stack.pop
        end
      end

      routes
    end

    private def current_prefix(proc_prefix : String, prefix_stack : Array(Tuple(Int32, String))) : String
      prefix_stack.reduce(proc_prefix) { |acc, entry| join_url(acc, entry[1]) }
    end

    private def line_to_routes(line : String, index : Int32, offset : Int32, prefix : String) : Array(RouteHit)
      result = [] of RouteHit
      handler = line.match(CODEREF_RE).try(&.[1])

      if m = line.match(VERB_STRING_RE)
        url = join_url(prefix, m[3])
        result << RouteHit.new(url, [http_method(m[1])], index, offset, handler)
      elsif m = line.match(VERB_QR_RE)
        body = m[2]? || m[3]? || m[4]? || m[5]? || m[6]? || ""
        url = join_url(prefix, regex_route_path(body))
        result << RouteHit.new(url, [http_method(m[1])], index, offset, handler)
      elsif m = line.match(ANY_LIST_RE)
        url = join_url(prefix, m[3])
        methods = methods_from_list(m[1])
        methods = ANY_METHODS if methods.empty?
        result << RouteHit.new(url, methods, index, offset, handler)
      elsif m = line.match(ANY_BARE_RE)
        url = join_url(prefix, m[2])
        result << RouteHit.new(url, ANY_METHODS.dup, index, offset, handler)
      end

      result
    end

    private def body_for_route(content : String,
                               route : RouteHit,
                               search_limit : Int32,
                               named_bodies : Hash(String, Noir::PerlCalleeExtractor::SubBody)?) : Tuple(String, Int32)?
      # A `=> \&handler` route has no inline `sub`, so resolve it straight
      # from the named-sub index. Scanning forward would otherwise latch
      # onto an unrelated `sub` (e.g. a following `prefix ... => sub {`).
      if name = route.handler_name
        if named_bodies && (sub = named_bodies[name]?)
          return {sub[:body], sub[:start_line]}
        end
        return
      end

      Noir::PerlCalleeExtractor.extract_sub_after(content, route.char_offset, search_limit)
    end

    private def http_method(verb : String) : String
      v = verb.downcase
      v == "del" ? "DELETE" : v.upcase
    end

    private def methods_from_list(spec : String) : Array(String)
      methods = [] of String
      spec.scan(/[A-Za-z]+/) do |m|
        token = m[0].downcase
        next if token == "qw"
        methods << http_method(token) if ANY_LIST_VERBS.includes?(token)
      end
      methods.uniq
    end

    # Best-effort URL for a regex route (`qr{/product/(\d+)}`): use the
    # pattern body as the path so the endpoint stays visible, anchor it
    # at `/`, and surface named captures (`(?<id>...)`) as path params.
    private def regex_route_path(body : String) : String
      path = body.strip
      path = path.lchop('^') if path.starts_with?('^')
      path = path.rchop('$') if path.ends_with?('$')
      return "/" if path.empty?
      path.starts_with?('/') ? path : "/#{path}"
    end

    private def extract_path_params(url : String) : Array(Param)
      params = [] of Param
      url.scan(/:([A-Za-z_][A-Za-z0-9_]*)/) do |m|
        params << Param.new(m[1], "", "path")
      end
      url.scan(/\(\?<([A-Za-z_][A-Za-z0-9_]*)>/) do |m|
        params << Param.new(m[1], "", "path")
      end
      params
    end

    private def extract_params_from_body(body : String, method : String) : Array(Param)
      params = [] of Param
      read_method = method == "GET" || method == "HEAD" || method == "OPTIONS"

      body.scan(/\broute_parameters\s*->\s*(?:get(?:_all)?\s*\(\s*['"]([^'"]+)['"]|\{\s*['"]?([A-Za-z_][A-Za-z0-9_-]*))/) do |m|
        name = m[1]? || m[2]?
        params << Param.new(name, "", "path") if name
      end

      body.scan(/\bquery_parameters\s*->\s*(?:get(?:_all)?\s*\(\s*['"]([^'"]+)['"]|\{\s*['"]?([A-Za-z_][A-Za-z0-9_-]*))/) do |m|
        name = m[1]? || m[2]?
        params << Param.new(name, "", "query") if name
      end

      body.scan(/\bbody_parameters\s*->\s*(?:get(?:_all)?\s*\(\s*['"]([^'"]+)['"]|\{\s*['"]?([A-Za-z_][A-Za-z0-9_-]*))/) do |m|
        name = m[1]? || m[2]?
        params << Param.new(name, "", "form") if name
      end

      body.scan(/\bupload\s*\(\s*['"]([^'"]+)['"]/) do |m|
        params << Param.new(m[1], "", "form")
      end

      body.scan(/->\s*header\s*\(\s*['"]([^'"]+)['"]/) do |m|
        params << Param.new(m[1], "", "header")
      end

      body.scan(/\bcookies?\s*(?:->\s*\{\s*['"]?([A-Za-z_][A-Za-z0-9_-]*)|\(\s*['"]([^'"]+)['"])/) do |m|
        name = m[1]? || m[2]?
        params << Param.new(name, "", "cookie") if name
      end

      # Legacy mixed-source accessors: `param('x')` and `params->{x}`.
      # Bucket by HTTP method since the source is ambiguous.
      param_type = read_method ? "query" : "form"
      body.scan(/(?<![:\w>])param\s*\(\s*['"]([^'"]+)['"]/) do |m|
        params << Param.new(m[1], "", param_type)
      end
      body.scan(/\bparams\s*->\s*\{\s*['"]?([A-Za-z_][A-Za-z0-9_-]*)/) do |m|
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

    private def normalize_prefix(prefix : String) : String
      cleaned = prefix.strip
      return "" if cleaned.empty? || cleaned == "/"
      cleaned
    end

    private def join_url(prefix : String, leaf : String) : String
      cleaned_leaf = strip_type_constraints(leaf)
      return normalize_url(cleaned_leaf) if prefix.empty?
      return normalize_url(prefix) if cleaned_leaf.empty?

      base = prefix.size > 1 ? prefix.chomp('/') : prefix
      tail = cleaned_leaf.starts_with?('/') ? cleaned_leaf : "/#{cleaned_leaf}"
      normalize_url("#{base}#{tail}")
    end

    # Drop Dancer2 type constraints (`:id[Int]`) from the displayed URL
    # while leaving the placeholder name intact.
    private def strip_type_constraints(path : String) : String
      path.gsub(/(:[A-Za-z_][A-Za-z0-9_]*)\[[^\]]*\]/, "\\1")
    end

    private def normalize_url(path : String) : String
      normalized = path.empty? ? "/" : path
      normalized = "/#{normalized}" unless normalized.starts_with?('/')
      normalized.size > 1 && normalized.ends_with?('/') ? normalized.rchop : normalized
    end

    private def brace_delta(line : String) : Int32
      delta = 0
      line.each_char do |char|
        delta += 1 if char == '{'
        delta -= 1 if char == '}'
      end
      delta
    end

    private def code_only_lines(pod_blanked : Array(String)) : Array(String)
      Noir::PerlCalleeExtractor.strip_non_code(pod_blanked.join('\n')).lines
    end

    private def line_offsets(content : String) : Array(Int32)
      offsets = [0]
      content.each_char_with_index do |char, index|
        offsets << index + 1 if char == '\n'
      end
      offsets
    end

    # POD blocks (`=head1` ... `=cut`) and `__END__`/`__DATA__` sections
    # are documentation/data, not code. Blank them while preserving the
    # original line count so endpoint line numbers stay aligned with the
    # source file.
  end
end
