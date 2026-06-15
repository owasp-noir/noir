require "../../../models/framework_tagger"
require "../../../models/endpoint"

# Go security-middleware tagger.
#
# `go_auth` already classifies *authentication* middleware (JWT/session/…).
# This tagger covers the other security middleware Go web frameworks expose —
# the protections a reviewer wants mapped onto each endpoint because, unlike
# Rails, Go frameworks ship none of them on by default. Their *presence* is
# the signal: which routes carry CSRF tokens, security headers, a rate limit,
# or a request-body cap, and (by their absence on a state-changing route)
# which don't.
#
# Detection mirrors `go_auth`: a pre-scan records group-level `.Use(...)`
# middleware against the group's URL prefix, then each endpoint is matched
# against inline middleware on its own route call and against the
# prefix-scoped group middleware. Everything is line-based and best-effort.
#
# Precision over recall: the indirect form (`mw := limiter.New(...)` then a
# bare `api.Use(mw)`) is deliberately *not* resolved — a false "protected"
# tag is worse for a security review than a miss, so only middleware named
# directly at the registration site is tagged. Cross-file middleware
# factories are likewise out of scope by design.
class GoSecurityTagger < FrameworkTagger
  # Security middleware constructors/identifiers, each mapped to the tag it
  # produces. Patterns are tied to the concrete constructor (`middleware.CSRF`,
  # `csrf.New`, `helmet.New`, …) so a plain local called `secure` or `limiter`
  # can't trip them. `wrapper: true` marks the net/http-style helpers
  # (gorilla/csrf, unrolled/secure, nosurf) that wrap the root handler rather
  # than register via `.Use` — those apply globally.
  SECURITY_MIDDLEWARE = [
    # --- CSRF protection ---
    {pattern: /middleware\.CSRF(?:WithConfig)?\s*\(/, tag: "csrf-protection", desc: "Echo CSRF middleware", wrapper: false},
    {pattern: /\bcsrf\.New\s*\(/, tag: "csrf-protection", desc: "Fiber CSRF middleware", wrapper: false},
    {pattern: /\bcsrf\.Protect\s*\(/, tag: "csrf-protection", desc: "gorilla/csrf protection", wrapper: true},
    {pattern: /\bcsrf\.Middleware\s*\(/, tag: "csrf-protection", desc: "gin-csrf middleware", wrapper: false},
    {pattern: /\bnosurf\.New(?:Pure)?\s*\(/, tag: "csrf-protection", desc: "nosurf CSRF middleware", wrapper: true},
    # --- Security response headers (XSS/clickjacking/HSTS/nosniff/…) ---
    {pattern: /middleware\.Secure(?:WithConfig)?\s*\(/, tag: "security-headers", desc: "Echo Secure (security headers) middleware", wrapper: false},
    {pattern: /\bhelmet\.New\s*\(/, tag: "security-headers", desc: "Fiber Helmet (security headers) middleware", wrapper: false},
    {pattern: /\bsecure\.New\s*\(/, tag: "security-headers", desc: "secure (security headers) middleware", wrapper: true},
    # --- Rate limiting / throttling ---
    {pattern: /middleware\.RateLimiter(?:WithConfig)?\s*\(/, tag: "rate-limit", desc: "Echo RateLimiter middleware", wrapper: false},
    {pattern: /middleware\.Throttle(?:Backlog)?\s*\(/, tag: "rate-limit", desc: "go-chi Throttle middleware", wrapper: false},
    {pattern: /\blimiter\.New\s*\(/, tag: "rate-limit", desc: "rate-limiter middleware", wrapper: false},
    {pattern: /\bhttprate\.(?:Limit|LimitByIP|LimitByRealIP|LimitAll)\s*\(/, tag: "rate-limit", desc: "go-chi/httprate rate limiting", wrapper: false},
    {pattern: /\btollbooth\.(?:LimitHandler|LimitFuncHandler|LimitByKeys)\s*\(/, tag: "rate-limit", desc: "tollbooth rate limiting", wrapper: false},
    # --- Request body size cap (DoS guard) ---
    {pattern: /middleware\.BodyLimit\s*\(/, tag: "body-limit", desc: "Echo BodyLimit (request body size cap) middleware", wrapper: false},
    {pattern: /\blimits\.RequestSizeLimiter\s*\(/, tag: "body-limit", desc: "gin-contrib/size request body size cap", wrapper: false},
    # --- Request timeout (resource-exhaustion guard) ---
    {pattern: /middleware\.Timeout(?:WithConfig)?\s*\(/, tag: "timeout", desc: "request timeout middleware", wrapper: false},
    {pattern: /\btimeout\.New(?:WithContext)?\s*\(/, tag: "timeout", desc: "Fiber timeout middleware", wrapper: false},
    # --- CORS (cross-origin resource sharing) ---
    {pattern: /middleware\.CORS(?:WithConfig)?\s*\(/, tag: "cors", desc: "Echo CORS middleware (review allowed origins/credentials)", wrapper: false},
    {pattern: /\bcors\.New\s*\(/, tag: "cors", desc: "CORS middleware (review allowed origins/credentials)", wrapper: true},
    {pattern: /\bcors\.Default\s*\(/, tag: "cors", desc: "gin-contrib/cors Default() — permissive: all origins allowed", wrapper: false},
    {pattern: /\bcors\.AllowAll\s*\(/, tag: "cors", desc: "rs/cors AllowAll() — permissive: all origins allowed", wrapper: true},
    {pattern: /\bhandlers\.CORS\s*\(/, tag: "cors", desc: "gorilla/handlers CORS (review allowed origins/credentials)", wrapper: true},
    # --- Cookie confidentiality/integrity ---
    {pattern: /\bencryptcookie\.New\s*\(/, tag: "secure-cookies", desc: "Fiber encrypted-cookie middleware", wrapper: false},
  ] of NamedTuple(pattern: Regex, tag: String, desc: String, wrapper: Bool)

  # A `.Use(...)` / `.Pre(...)` middleware registration call.
  USE_CALL = /(\w+)\.(?:Use|Pre)\s*\(/

  # A route-definition call. Used only to *exclude* route lines from the
  # global-wrapper branch (inline route middleware is handled per-endpoint),
  # so an over-broad verb set here is safe.
  ROUTE_DEF = /\b(?:GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD|CONNECT|TRACE|Get|Post|Put|Delete|Patch|Options|Head|Connect|Trace|Any|All|Handle|HandleFunc|Match|Add)\s*\(/

  # `name := parent.Group("/seg")` style group declaration (no closure arg).
  ASSIGN_GROUP = /(\w+)\s*:?=\s*(\w+)\.Group\s*\(\s*"([^"]*)"/

  # `parent.Group("/seg", func(...)` / `.Route` / `.Party` closure group.
  CLOSURE_GROUP = /(\w+)\.(?:Group|Route|Party|PartyFunc|Mount)\s*\(\s*"([^"]*)"\s*,\s*func/

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "go_security"
    @middleware_scopes = [] of NamedTuple(prefix: String, tag: String, description: String)
  end

  def self.target_techs : Array(String)
    [
      "go_echo", "go_gin", "go_chi", "go_fiber",
      "go_beego", "go_mux", "go_fasthttp",
      "go_gozero", "go_goyave",
      "go_hertz", "go_iris", "go_gf",
    ]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    pre_scan_middleware_scopes
    endpoints.each { |endpoint| check_endpoint(endpoint) }
    endpoints
  end

  # Phase 1: walk every .go file and record where security middleware is
  # registered, resolved to the URL prefix it guards.
  private def pre_scan_middleware_scopes
    @middleware_scopes.clear

    collect_files_by_extension(".go").each do |file|
      content = read_file(file)
      next if content.nil?
      scan_group_middleware(content)
    end

    @middleware_scopes.uniq!
  end

  private def scan_group_middleware(content : String)
    # variable name -> resolved URL prefix (assignment-style groups)
    group_vars = {} of String => String
    # active closure-group prefixes, with the brace depth they live above
    scope_stack = [] of NamedTuple(threshold: Int32, prefix: String)
    depth = 0

    content.each_line do |line|
      stripped = line.strip

      # Closure group: push its prefix; it stays active until braces unwind.
      if m = stripped.match(CLOSURE_GROUP)
        base = resolve_receiver(m[1], group_vars, scope_stack)
        scope_stack << {threshold: depth, prefix: join_prefix(base, m[2])}
      end

      # Assignment group: remember the variable's prefix for later `.Use`.
      if m = stripped.match(ASSIGN_GROUP)
        base = resolve_receiver(m[2], group_vars, scope_stack)
        group_vars[m[1]] = join_prefix(base, m[3])
      end

      register_security_scopes(stripped, group_vars, scope_stack)

      # Update brace depth and retire any closure scopes that just closed.
      depth += line.count('{') - line.count('}')
      while !scope_stack.empty? && depth <= scope_stack.last[:threshold]
        scope_stack.pop
      end
    end
  end

  private def register_security_scopes(stripped : String, group_vars, scope_stack)
    use_receiver = stripped.match(USE_CALL).try &.[1]

    SECURITY_MIDDLEWARE.each do |mw|
      next unless stripped.matches?(mw[:pattern])

      if use_receiver
        # `receiver.Use(middleware.X())` — scope to the receiver's group.
        prefix = prefix_for(resolve_receiver(use_receiver, group_vars, scope_stack))
      elsif mw[:wrapper] && !stripped.matches?(ROUTE_DEF)
        # net/http wrapper around the root handler — applies globally. Route
        # lines are skipped (their inline middleware is tagged per-endpoint).
        prefix = prefix_for(current_scope(scope_stack))
      else
        next
      end

      @middleware_scopes << {prefix: prefix, tag: mw[:tag], description: mw[:desc]}
    end
  end

  # Phase 2: tag each endpoint from inline route middleware + group scopes.
  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      content = read_file(path_info.path)
      next if content.nil?

      lines = content.split("\n")
      line_num = path_info.line
      next if line_num.nil?
      next if line_num < 1 || line_num > lines.size

      tag_inline_route_middleware(endpoint, lines, line_num - 1)
    end

    @middleware_scopes.each do |scope|
      next unless prefix_covers?(scope[:prefix], endpoint.url)

      # A broad root/global ("/") scope sweeps in static-asset routes (the
      # SPA shell, `/static/*`, favicon, `*.js`/`*.css`) that are either
      # served outside the middleware chain (e.g. registered before a global
      # `g.Use(cors.New(...))`, as in gotify) or simply aren't a meaningful
      # CORS/CSRF/headers review target. Skip them — inline route middleware
      # and specific-prefix scopes are unaffected, so a genuinely guarded
      # asset route keeps its tag.
      next if scope[:prefix] == "/" && static_asset_route?(endpoint.url)

      endpoint.add_tag(Tag.new(scope[:tag], scope[:description], "go_security"))
    end
  end

  # Scan only the current route call's own lines (paren-balanced from the
  # route line) for trailing route-level middleware such as Echo's
  # `e.POST(path, handler, middleware.CSRF())`. Bounding to the route call's
  # extent keeps a following sibling's `group.Use(...)` from leaking in.
  private def tag_inline_route_middleware(endpoint : Endpoint, lines : Array(String), start_idx : Int32)
    # The route call always opens its paren on its own line. If the line ref
    # doesn't (a stale/misaligned location), bail rather than scan forward —
    # otherwise the loop would run to `limit` and could pick up a following
    # group's `.Use(...)` and tag the wrong endpoint.
    return unless lines[start_idx].includes?('(')

    depth = 0
    opened = false
    idx = start_idx
    limit = [start_idx + 12, lines.size - 1].min

    while idx <= limit
      line = lines[idx]

      SECURITY_MIDDLEWARE.each do |mw|
        if line.matches?(mw[:pattern])
          endpoint.add_tag(Tag.new(mw[:tag], "#{mw[:desc]} (inline on route)", "go_security"))
        end
      end

      depth += line.count('(') - line.count(')')
      opened = true if line.includes?('(')
      break if opened && depth <= 0
      idx += 1
    end
  end

  # Resolve a receiver token to its URL prefix: a tracked group variable, the
  # innermost active closure group, or "" (the root router / global scope).
  private def resolve_receiver(receiver : String?, group_vars, scope_stack) : String
    return current_scope(scope_stack) if receiver.nil?
    if gp = group_vars[receiver]?
      gp
    else
      current_scope(scope_stack)
    end
  end

  private def current_scope(scope_stack) : String
    scope_stack.empty? ? "" : scope_stack.last[:prefix]
  end

  private def prefix_for(prefix : String) : String
    prefix.empty? ? "/" : prefix
  end

  # Join a base prefix and a new path segment into a normalized URL prefix:
  #   ("", "/web") -> "/web"   ("/api", "v1") -> "/api/v1"
  private def join_prefix(base : String, seg : String) : String
    parts = "#{base}/#{seg}".split("/").reject(&.empty?)
    parts.empty? ? "/" : "/" + parts.join("/")
  end

  # Segment-aware prefix match so "/web" guards "/web/x" but not "/website".
  # The root scope "/" guards every endpoint.
  private def prefix_covers?(prefix : String, url : String) : Bool
    return true if prefix == "/"
    url == prefix || url.starts_with?("#{prefix}/")
  end
end
