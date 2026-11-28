require "uri"
require "../models/endpoint"
require "../techs/techs"
require "./url_path"
require "./http_symbols"
require "./utils"

# Shared request-to-route matching for trace and service links.
module Noir::RouteMatcher
  extend self

  # ---- trace: concrete request path → declared route ----------------------

  # `{id}` `:id` `<int:pk>` `[id]` `$id` `${id}` match one segment; `*`
  # `**` `{path*}` `{...rest}` `[...slug]` `[[...slug]]` `*path` `:rest*` `<path:p>`
  # `{*path}` (Spring, ASP.NET, Next.js and Starlette's `{p:path}` as the
  # optimizer writes them) and `{path...}` (Ktor, Go) match the rest
  # (Express's bare `*` is a catch-all, not one segment).
  REST_PLACEHOLDER = /\A(?:<path:[^>]*>|\*\*|\{\*(?:[^{}]|\{[^{}]*\})*\}|\{[^}]*\*\}|\{\.\.\.[^}]*\}|\{[^}]*\.\.\.\}|\{[A-Za-z_]\w*:(?:\.\*|\.\+)\}|\[\[\.\.\.[^\]]*\]\]|\[\.\.\.[^\]]*\]|\*[A-Za-z_]\w*|:[A-Za-z_]\w*[*+]|\*)/
  # The rest placeholders that also take zero segments, so `/files/:path*`
  # serves `/files` too.
  ZERO_OR_MORE = /\A(?:\*\*|\{\*(?:[^{}]|\{[^{}]*\})*\}|\{[^}]*(?:\*|\.\.\.)\}|\{[A-Za-z_]\w*:\.\*\}|:\w+\*|\[\[)/
  # Where `{*name}` needs at least one segment: Next.js `[...slug]` (its
  # optional `[[...slug]]` is written as a second, bare route), axum and a
  # gRPC-transcoding `{name=**}`. Spring, ASP.NET, Armeria, salvo's
  # `{*name}` / `{**name}` and Rocket's `<name..>` take zero.
  ONE_OR_MORE_STAR_TECHS = Set{"js_nextjs", "rust_axum", "grpc"}
  # path-to-regexp v8 (Express 5) optional group: `/posts{/:id}`.
  OPTIONAL_GROUP = /\A\{(\/[^{}]*)\}/
  # `:id(\d+)` (Express 4 / Koa / Fastify) and `:id{[0-9]+}` (Hono) carry a
  # regex constraint; a trailing `?` makes the segment optional.
  # Play's `$id<\w{8}>` is one placeholder with its regex.
  ONE_PLACEHOLDER  = /\A(?:\$\{[^}]*\}|\{(?:[^{}]|\{[^{}]*\})*\}|<[^>]*>|\[[^\]]*\]|:[A-Za-z_]\w*(?:\((?:[^()]|\([^()]*\))*\)|\{(?:[^{}]|\{[^{}]*\})*\})?\??|\$[A-Za-z_]\w*(?:<[^>]*>)?)/
  PLACEHOLDER_CHAR = /[{:<\[$*]/

  # The regex a declared route matches request paths against, or nil for a
  # pattern Noir cannot turn into one.
  def route_regex(endpoint : Endpoint, ignore_case : Bool = false) : Regex?
    options = ignore_case ? Regex::Options::IGNORE_CASE : Regex::Options::None
    # The request is compared without its trailing slash, so the route loses
    # its own first: Django's `x/<int:pk>/` must match `/x/5`.
    route = strip_trailing_slash(request_path(endpoint.url))
    if endpoint.regex_path?
      # Grouped, so each branch of an alternation is anchored.
      return Regex.new("\\A(?:#{URLPath.strip_regex_anchors(route).rchop('/')})/?\\z", options) rescue nil
    end
    technology = endpoint.details.technology || ""
    star_needs_one = ONE_OR_MORE_STAR_TECHS.includes?(technology)
    # Hono's trailing `/*` also serves the path before it: `/static/*`
    # answers `/static`. Express, Koa and Fastify need the slash.
    if technology == "js_hono" && route.ends_with?("/*")
      return Regex.new("\\A#{route_pattern(route.rchop("/*"), star_needs_one)}(?:/.*)?\\z", options) rescue nil
    end
    Regex.new("\\A#{route_pattern(route, star_needs_one)}/?\\z", options) rescue nil
  end

  # Routers that match literal path text without regard to case by default:
  # ASP.NET (MVC, Web API, Razor Pages, minimal APIs, ...) and Express/Koa
  # (`caseSensitive` / `sensitive` default false). Rails, Django, Flask,
  # Spring, Laravel, Go routers and Fastify are case-sensitive.
  # ponytail: tech-name list; a router configured the other way round is not modelled.
  CASE_INSENSITIVE_ROUTER_TECHS = Set{"js_express", "js_koa", "vb_aspnet_mvc"}

  def case_insensitive_router?(endpoint : Endpoint) : Bool
    technology = endpoint.details.technology || ""
    CASE_INSENSITIVE_ROUTER_TECHS.includes?(technology) || technology.starts_with?("cs_aspnet")
  end

  private def route_pattern(route : String, star_needs_one : Bool = false) : String
    parts = [] of String
    scan_placeholders(route) do |kind, text|
      case kind
      when :rest
        # ASP.NET `{**path:regex(^(?!api/).*)}`: the rest must satisfy the
        # constraint, so `/api/x` is not served by the SPA fallback it excludes.
        constraint = rest_constraint(text)
        guard = constraint ? "(?=(?:#{constraint})\\z)" : ""
        if text.matches?(ZERO_OR_MORE) && parts.last? == "/" && !(star_needs_one && text.starts_with?("{*"))
          parts.pop
          # With a constraint the empty rest must satisfy it too.
          empty_ok = constraint.nil? || Regex.new("\\A(?:#{constraint})\\z").matches?("")
          parts << "(?:/#{guard}.*)#{empty_ok ? "?" : ""}"
        else
          parts << "#{guard}.*"
        end
      when :optional then parts << "(?:#{route_pattern(text, star_needs_one)})?"
      when :one
        if (text.starts_with?(':') && text.ends_with?('?')) || (text.starts_with?('{') && text.ends_with?("?}"))
          # Express 4 `:id?` and ASP.NET `{id?}` make the slash before them
          # optional too: `/posts/:id?` serves both `/posts` and `/posts/5`.
          slash = parts.last? == "/" ? parts.pop : ""
          required = text.ends_with?('?') ? text.rchop('?') : "#{text.rchop("?}")}}"
          parts << "(?:#{slash}#{typed_segment(required)})?"
        else
          parts << typed_segment(text)
        end
      else parts << Regex.escape(text)
      end
    end
    parts.join
  end

  # The regex of a `{*name:regex(..)}` / `{**name:regex(..)}` catch-all,
  # anchors stripped, or nil when it has none or does not compile.
  private def rest_constraint(text : String) : String?
    if m = text.match(/\A\{[A-Za-z_]\w*:(\.\*|\.\+)\}\z/)
      return m[1]
    end
    body = text.match(/\A\{\*{1,2}\w+:regex\((.*)\)\}\z/m).try(&.[1]) || return
    # .NET character-class subtraction (`[a-z-[aeiou]]`) has no PCRE form: no
    # constraint rather than a wrong one.
    return if body.includes?("-[")
    # ASP.NET wraps the constraint as `^(...)$`, so an anchor belongs to its
    # own alternative, not to the whole text.
    body = split_alternatives(body).map { |alternative| strip_anchors(alternative) }.join('|')
    Regex.new(body)
    body
  rescue ArgumentError
    nil
  end

  private def strip_anchors(alternative : String) : String
    alternative = alternative.lchop('^')
    alternative.ends_with?("\\$") ? alternative : alternative.rchop('$')
  end

  # Splits at the `|` outside groups, classes and escapes.
  private def split_alternatives(body : String) : Array(String)
    parts = [] of String
    depth = 0
    in_class = false
    current = String::Builder.new
    chars = body.chars
    index = 0
    while index < chars.size
      char = chars[index]
      if char == '\\' && index + 1 < chars.size
        current << char << chars[index + 1]
        index += 2
        next
      end
      if in_class
        in_class = false if char == ']'
      elsif char == '['
        in_class = true
      elsif char == '('
        depth += 1
      elsif char == ')'
        depth -= 1
      elsif char == '|' && depth == 0
        parts << current.to_s
        current = String::Builder.new
        index += 1
        next
      end
      current << char
      index += 1
    end
    parts << current.to_s
    parts
  end

  # A typed placeholder only takes what the router would route to it:
  # Werkzeug/Django `<int:id>` / `<uuid:id>`, ASP.NET `{id:int}` /
  # `{id:guid}`, and a chi / gorilla regex constraint (`{type:issues}`,
  # `{action:star|unstar}`). `/v1/datasets/kb-legal/documents` is not
  # `/v1/datasets/<uuid:dataset_id>/documents`, and `/o/r/info/refs` is not
  # `/{owner}/{repo}/{type:issues}/{index}`.
  private def typed_segment(placeholder : String) : String
    case placeholder
    when /\A<int:|\A\{\w+:(?:int|long)\}\z/ then "\\d+"
    when /\A<uuid:|\A\{\w+:guid\}\z/        then "[0-9a-fA-F]{8}-?(?:[0-9a-fA-F]{4}-?){3}[0-9a-fA-F]{12}"
    when /\A\{\w+:([^\/]+)\}\z/             then constraint_segment($1)
    when /\A:\w+[({](.+)[)}]\z/             then constraint_segment($1)
    when /\A\$\w+<(.+)>\z/                  then constraint_segment($1)
    else                                         "[^/]+"
    end
  end

  # A `{name:regex}` constraint as one segment's pattern, anchored the way
  # chi anchors it (a leading `^` / trailing `$` is optional there). A regex
  # that does not compile takes any one segment.
  # ponytail: a `.` or negated class in the constraint can still match a `/`;
  # confine it to the segment if a real route ever relies on that.
  private def constraint_segment(constraint : String) : String
    body = constraint.lchop('^')
    body = body.rchop('$') unless body.ends_with?("\\$")
    Regex.new(body)
    "(?:#{body})"
  rescue ArgumentError
    "[^/]+"
  end

  # Walks a route, yielding `:rest` / `:one` placeholders and `:literal`
  # characters in order. A `:verb` right after a `}` is a gRPC-transcoding
  # custom method (`/v1/{name}:cancel`), literal text rather than a param.
  private def scan_placeholders(route : String, &)
    scanner = route
    taken = ""
    until scanner.empty?
      if taken.ends_with?('}') && scanner.starts_with?(':')
        taken = ":"
        yield :literal, taken
      elsif m = scanner.match(REST_PLACEHOLDER)
        taken = m[0]
        yield :rest, taken
      elsif m = scanner.match(OPTIONAL_GROUP)
        yield :optional, m[1]
        taken = m[0]
      elsif m = scanner.match(ONE_PLACEHOLDER)
        taken = m[0]
        yield :one, taken
      else
        taken = scanner[0].to_s
        yield :literal, taken
      end
      scanner = scanner[taken.size..]
    end
  end

  # How specific a route is: fewer catch-all segments, then fewer placeholders,
  # then more literal text. `/u/:id` outranks `/*proxyPath` for `/u/5`.
  # Among routes with a catch-all the literal text comes first:
  # `/media/:id/*any` is more specific than `/*unmatched_route`, though it
  # has one more param.
  def specificity(url : String) : {Int32, Int32, Int32, Int32}
    rest = 0
    one = 0
    literal = 0
    constrained = 0
    scan_placeholders(strip_trailing_slash(request_path(url))) do |kind, text|
      case kind
      when :rest then rest += 1
      when :one, :optional
        one += 1
        constrained += 1 if kind == :one && typed_segment(text) != "[^/]+"
      else literal += text.size
      end
    end
    rest > 0 ? {rest, -literal, one, -constrained} : {rest, one, -literal, -constrained}
  end

  private def strip_trailing_slash(path : String) : String
    while path.size > 1 && path.ends_with?('/')
      path = path.rchop('/')
    end
    path
  end

  # The path part of an endpoint URL: `-u` prefixes a scheme+host. Any
  # other scheme (`ws://`, `cli://shopctl/users`, a deep link) names the
  # surface, so it stays: `/users` is not the CLI's `users` command.
  def request_path(url : String) : String
    if url =~ %r{\Ahttps?://[^/]*(/.*)?\z}i
      path = $~[1]? || "/"
      return path
    end
    url
  end

  private def normalize(path : String) : String
    strip_trailing_slash(request_path(path).split('#', 2)[0].split('?', 2)[0])
  end

  # The path a client sent, as a router sees it: no query or fragment, a
  # leading `/`, `//` collapsed, each segment percent-decoded (`%2F` stays
  # one segment, since a router splits before it decodes). A declared route
  # is written decoded, so `/%C3%A9t%C3%A9` has to be read as `/été`.
  def request_target(path : String) : String
    path = request_path(path).split('#', 2)[0].split('?', 2)[0]
    return path if path.includes?("://")
    path = "/#{path}" unless path.starts_with?('/')
    path.gsub(%r{/{2,}}, "/").split('/', remove_empty: false).map do |segment|
      segment.includes?('%') ? URI.decode(segment).gsub('/', "%2F") : segment
    rescue URI::Error
      segment
    end.join('/')
  end

  # Whether `query --method` lists a route declared for `declared`. An
  # `ANY` row (nginx, Apache, `router.all`) serves every HTTP verb, so
  # `--method POST` lists it, as `trace` does; `--method ANY` lists only
  # the `ANY` rows.
  def method_listed?(methods : Array(String), declared : String) : Bool
    declared = declared.upcase
    methods.includes?(declared) || (::synthetic_any_method?(declared) && methods.any? { |m| ::ALLOWED_HTTP_METHODS.includes?(m) })
  end

  record Match, endpoint : Endpoint, matched_by : String

  # Proxy rules that serve every path under their own, by the path-type tag
  # the analyzer sets: nginx `location /api/`, haproxy `path_beg` and Istio
  # `prefix` compare strings (`/api` serves `/apis`); Ingress and Gateway
  # API `Prefix` compare whole segments. A Go ServeMux pattern ending in `/`
  # serves its subtree (gin's or Echo's `/x/` is one route, and `/x/{$}`
  # only `/x/`).
  #
  # A proxy rule merged into a code route (an Ingress `Prefix` folded into
  # `POST /api/users`) keeps its tag, but the code serves only its own
  # route, so the proxy tags count only on a row no code analyzer reported.
  STRING_PREFIX_TAGS = {
    "nginx-path-type" => {"prefix", "prefix-stop"}, "haproxy-path-type" => {"prefix"},
    "virtualservice-path-type" => {"prefix"}, "go-http-path-type" => {"subtree"},
  }
  SEGMENT_PREFIX_TAGS = {"ingress-path-type" => {"prefix"}, "gateway-path-type" => {"pathprefix"}}
  CODE_PREFIX_TAGS    = Set{"go-http-path-type"}

  # Whether `endpoint` serves `path` (query and fragment already dropped)
  # under one of those prefix rules.
  private def prefix_serves?(endpoint : Endpoint, path : String) : Bool
    technologies = endpoint.details.technologies.empty? ? [endpoint.details.technology || ""] : endpoint.details.technologies
    proxy_only = technologies.all? { |technology| NoirTechs::DECLARATION_TECHS.includes?(technology) }
    route = request_path(endpoint.url)
    return path.starts_with?(route) if endpoint.tags.any? { |t| prefix_tag?(t, STRING_PREFIX_TAGS, proxy_only) }
    return false unless endpoint.tags.any? { |t| prefix_tag?(t, SEGMENT_PREFIX_TAGS, proxy_only) }
    route = strip_trailing_slash(route)
    route == "/" || path.starts_with?("#{route}/")
  end

  private def prefix_tag?(tag : Tag, table, proxy_only : Bool) : Bool
    return false unless table[tag.name]?.try(&.includes?(tag.description))
    proxy_only || CODE_PREFIX_TAGS.includes?(tag.name)
  end

  # Whether a route declared for `declared` serves a `wanted` request method.
  # Frameworks answer HEAD from the GET route, so a HEAD request traces to it.
  def method_serves?(declared : String, wanted : String?) : Bool
    return true unless wanted
    declared = declared.upcase
    declared == wanted || ::synthetic_any_method?(declared) || (wanted == "HEAD" && declared == "GET")
  end

  RAILS_FORMAT_SUFFIX = /\.[A-Za-z0-9]+\z/
  FORMAT_SUFFIX_TECHS = Set{"ruby_rails", "ruby_grape"}

  # Routes matching a concrete request, exact matches first. A PHP front
  # controller also answers its routes under another spelling: `/index.php/x`
  # is `/x` (PATH_INFO routing, Nextcloud without pretty URLs), and Nextcloud
  # serves `/ocs/v2.php/...` as `/ocs/v1.php/...` too. Those are tried
  # against the PHP routes when the request itself matches nothing.
  #
  # A Rails route also answers with an optional `.format` suffix
  # (`/ai-llms.json` is `/ai-llms`), so when only a catch-all matched, the
  # suffix-less path is tried against the Rails routes and its matches lead.
  def trace(endpoints : Array(Endpoint), method : String?, path : String) : Array(Match)
    # A client declaration (Feign, `@HttpExchange`) mirrors a route another
    # service serves; the route this app serves leads, the stub follows.
    served, clients = trace_matches(endpoints, method, path).partition { |match| !match.endpoint.internal }
    served + clients
  end

  private def trace_matches(endpoints : Array(Endpoint), method : String?, path : String) : Array(Match)
    matches = trace_path(endpoints, method, path)
    wanted = strip_trailing_slash(request_target(path))
    if matches.none?(&.matched_by.in?("exact", "pattern", "exact_ci", "pattern_ci")) && (bare = wanted.sub(RAILS_FORMAT_SUFFIX, "")) != wanted && !bare.empty?
      formatted = endpoints.select { |endpoint| FORMAT_SUFFIX_TECHS.includes?(endpoint.details.technology || "") }
      matches = trace_path(formatted, method, bare).select(&.matched_by.in?("exact", "pattern", "exact_ci", "pattern_ci")) + matches unless formatted.empty?
    end
    return matches unless matches.empty?
    alias_path = if wanted.starts_with?("/index.php/")
                   wanted.lchop("/index.php")
                 elsif wanted.starts_with?("/ocs/v1.php/")
                   "/ocs/v2.php" + wanted.lchop("/ocs/v1.php")
                 end
    return matches unless alias_path
    php = endpoints.select { |endpoint| endpoint.details.technology.try(&.starts_with?("php_")) }
    trace_path(php, method, alias_path)
  end

  private def trace_path(endpoints : Array(Endpoint), method : String?, path : String) : Array(Match)
    unslashed = request_target(path)
    wanted = strip_trailing_slash(unslashed)
    exact = [] of Match
    pattern = [] of {Match, {Int32, Int32, Int32, Int32}}
    folded = [] of {Match, {Int32, Int32, Int32, Int32}}
    endpoints.each do |endpoint|
      next unless method_serves?(endpoint.method, method)
      route = normalize(request_path(endpoint.url))
      if route == wanted
        exact << Match.new(endpoint, "exact")
        # The pattern comes from the scanned source and may backtrack past PCRE2's
        # match limit, which raises instead of failing to match; that route is
        # then simply not the one that served the request.
      elsif (regex = route_regex(endpoint)) && regex_matches_bounded?(regex, wanted)
        spec = specificity(endpoint.url)
        pattern << {Match.new(endpoint, spec[0] > 0 ? "wildcard" : "pattern"), spec}
      elsif case_insensitive_router?(endpoint) && (route.compare(wanted, case_insensitive: true) == 0 || ((regex = route_regex(endpoint, true)) && regex_matches_bounded?(regex, wanted)))
        # A case-folded hit ranks below every case-exact pattern match.
        spec = specificity(endpoint.url)
        kind = route.compare(wanted, case_insensitive: true) == 0 ? "exact_ci" : (spec[0] > 0 ? "wildcard_ci" : "pattern_ci")
        folded << {Match.new(endpoint, kind), spec}
      elsif prefix_serves?(endpoint, unslashed)
        # Ranked as the catch-all it is: `/api/` reads as `/api/**`.
        pattern << {Match.new(endpoint, "prefix"), specificity("#{route.rchop('/')}/**")}
      end
    end
    # Most specific first, so `--limit 1` is the route a router would pick.
    pattern.sort_by!(&.[1])
    folded.sort_by! { |m, spec| {m.matched_by == "exact_ci" ? 0 : 1, spec} }
    # A route declared for the request's own method before an any-method
    # one at the same path (a proxy redirect rule beside the app's view).
    declared, any = exact.partition { |m| !method || !::synthetic_any_method?(m.endpoint.method.upcase) }
    declared + any + pattern.map(&.[0]) + folded.map(&.[0])
  end

  def literal_anchor?(url : String) : Bool
    anchored = false
    scan_placeholders(normalize(url)) do |kind, text|
      anchored = true if kind == :literal && text != "/"
    end
    anchored
  end

  # Two route templates can agree without choosing a value for a typed
  # parameter. Catch-all routes and optional groups are deliberately not equated.
  def template_shape(url : String) : String?
    parts = [] of String
    scan_placeholders(normalize(url)) do |kind, text|
      return if kind.in?(:rest, :optional)
      parts << (kind == :one ? "{}" : text)
    end
    parts.join
  end
end
