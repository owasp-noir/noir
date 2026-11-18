require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../ext/tree_sitter/tree_sitter"
require "./axum_chain"

# Rust-specific security tagger.
#
# `rust_auth` already classifies *authentication* (request guards,
# extractors, auth middleware), so this tagger covers the other
# framework-level *security protections* that a reviewer wants to know
# are (or are not) in front of an endpoint. Each protection maps onto a
# tag whose description says whether the configuration is hardened or a
# risk:
#
#   * cors             — CORS middleware. Permissive configs (any origin,
#                        wildcard) are flagged as a risk; restricted
#                        allow-lists are recorded as informational.
#   * rate-limit       — request throttling (actix-governor /
#                        tower_governor / actix-limitation / tower limit).
#   * security-headers — hardening response headers (HSTS, CSP,
#                        X-Frame-Options, X-Content-Type-Options, …).
#   * body-limit       — request body size cap (DoS mitigation). A
#                        disabled limit is flagged as a risk.
#
# Detection is two-pronged:
#
#   1. Source middleware — every `.rs` file is pre-scanned for the
#      builder calls above. The enclosing Actix `web::scope("/x")` (if
#      any) gives the URL prefix the protection applies to; app-wide
#      middleware (`App::new().wrap(..)`) maps to `/` so it tags every
#      endpoint. An axum `.layer(..)` covers the routes registered before
#      it on its router chain (see `layer_scope`). Test modules
#      (`#[cfg(test)]`) and `tests/`/`benches/`/`examples/` files are
#      skipped so test-only middleware can't taint real endpoints.
#
#   2. Loco config — Loco wires its middleware in `config/*.yaml`
#      (`middlewares: { cors:, limit_payload:, secure_headers: }`)
#      rather than in code, so those files are parsed too and applied
#      app-wide.
#
# Scope mapping errs toward false *negatives* (a too-narrow prefix tags
# fewer endpoints) rather than false positives, in keeping with the
# rest of Noir's tagging.
@[Noir::TaggerFor(key: "rust_security", name: "Rust Security Tagger", desc: "Identifies Rust framework security protections (CORS, rate limiting, security headers, body-size limits)", order: 80)]
class RustSecurityTagger < FrameworkTagger
  include RustAxumChain

  # Where a protection applies: under `prefix` bar the `except` routes, or,
  # when `mounts` is set, only on those router-local `{"route"|"nest", path}`
  # mounts (an axum `.layer(..)` whose routes were read).
  record Scope,
    prefix : String,
    mounts : Array({String, String})? = nil,
    except : Array(String) = [] of String

  # A single detected protection: the tag to emit, its human description,
  # where it applies, and whether it is a risk (risk variants win dedup so
  # the reviewer sees the alarming description, not the benign).
  record Protection,
    tag : String,
    description : String,
    scope : Scope,
    risk : Bool

  # The rows of an axum `.layer(..)` call's arguments and what it wraps.
  private record LayerSpan, first : Int32, last : Int32, scope : Scope

  # --- CORS -----------------------------------------------------------
  # Permissive: any origin is accepted. The classic finding.
  CORS_PERMISSIVE_PATTERNS = [
    {/Cors::permissive\s*\(/, "Cors::permissive()"},
    {/CorsLayer::permissive\s*\(/, "CorsLayer::permissive()"},
    {/CorsLayer::very_permissive\s*\(/, "CorsLayer::very_permissive()"},
    {/\.allow_any_origin\s*\(/, ".allow_any_origin()"},
    {/\.send_wildcard\s*\(/, ".send_wildcard()"},
    {/\.allow_origin\s*\(\s*Any\b/, ".allow_origin(Any)"},
    {/\.allowed_origin\s*\(\s*"\*"/, %(allowed_origin("*"))},
  ]

  # Configured (restricted) CORS — present but not wide open.
  CORS_PRESENT_PATTERNS = [
    {/Cors::default\s*\(/, "actix-cors"},
    {/CorsLayer::new\s*\(/, "tower-http CorsLayer"},
    {/\.allowed_origin\s*\(/, "actix-cors allow-list"},
    {/\.allow_origin\s*\(/, "tower-http allow-list"},
    {/\bCorsOptions\b/, "rocket-cors"},
  ]

  # --- Rate limiting --------------------------------------------------
  # Match the *application* of a limiter (`.wrap`/`.layer`) or a Layer
  # type that is only ever applied — never a bare `GovernorConfigBuilder`
  # value, which is config and would mis-map an app-wide tag onto every
  # endpoint even when the limiter is wrapped onto one scope.
  RATE_LIMIT_PATTERNS = [
    {/\.(?:wrap|layer|route_layer|attach)\s*\(\s*&?\s*[\w:]*Governor\b/, "governor"},
    {/\bGovernorLayer\b/, "tower_governor"},
    {/\bRateLimitLayer\b/, "tower RateLimitLayer"},
    {/\.(?:wrap|layer)\s*\(\s*&?\s*[\w:]*RateLimiter\b/, "rate limiter"},
    {/\bactix_limitation\b/, "actix-limitation"},
  ]

  # --- Security response headers --------------------------------------
  # The header name — as a quoted literal (`"X-Frame-Options"`) or the
  # `http` crate's `HeaderName` constant (`X_FRAME_OPTIONS`) — is a
  # strong signal the app sets it (request-side reads of these are rare).
  # Framework-agnostic: works for Actix `DefaultHeaders`, tower-http
  # `SetResponseHeaderLayer`, and helmet-style crates alike.
  SECURITY_HEADER_PATTERNS = [
    {/"[Ss]trict-[Tt]ransport-[Ss]ecurity"|\bSTRICT_TRANSPORT_SECURITY\b/, "Strict-Transport-Security (HSTS)"},
    {/"[Cc]ontent-[Ss]ecurity-[Pp]olicy"|\bCONTENT_SECURITY_POLICY\b/, "Content-Security-Policy"},
    {/"[Xx]-[Ff]rame-[Oo]ptions"|\bX_FRAME_OPTIONS\b/, "X-Frame-Options"},
    {/"[Xx]-[Cc]ontent-[Tt]ype-[Oo]ptions"|\bX_CONTENT_TYPE_OPTIONS\b/, "X-Content-Type-Options"},
    {/"[Rr]eferrer-[Pp]olicy"|\bREFERRER_POLICY\b/, "Referrer-Policy"},
    {/"[Pp]ermissions-[Pp]olicy"|\bPERMISSIONS_POLICY\b/, "Permissions-Policy"},
  ]

  # --- Request body size limit ----------------------------------------
  BODY_LIMIT_DISABLED_PATTERNS = [
    {/DefaultBodyLimit::disable\s*\(/, "DefaultBodyLimit::disable()"},
  ]

  BODY_LIMIT_PATTERNS = [
    {/DefaultBodyLimit::max\s*\(/, "axum DefaultBodyLimit"},
    {/\bDefaultBodyLimit\b/, "axum DefaultBodyLimit"},
    {/\bRequestBodyLimitLayer\b/, "tower-http RequestBodyLimitLayer"},
    {/\bPayloadConfig\b/, "actix PayloadConfig"},
    {/\b(?:Json|Form|Payload)Config\b[^=]*\.limit\s*\(/, "actix config limit"},
  ]

  ANY_PATTERN = Regex.union(
    (CORS_PERMISSIVE_PATTERNS + CORS_PRESENT_PATTERNS + RATE_LIMIT_PATTERNS +
     SECURITY_HEADER_PATTERNS + BODY_LIMIT_DISABLED_PATTERNS + BODY_LIMIT_PATTERNS).map(&.[0])
  )

  def initialize(options : Hash(String, YAML::Any))
    super
    @protections = [] of Protection
  end

  # Kept in lock-step with `rust_auth` (the guard-support invariant in
  # techs_spec requires every framework-tagger target to be a
  # guard-supported tech, which currently excludes Salvo/Poem).
  def self.target_techs : Array(String)
    [
      "rust_axum", "rust_rocket", "rust_actix_web",
      "rust_loco", "rust_rwf", "rust_tide",
      "rust_warp", "rust_gotham", "rust_ntex",
    ]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    pre_scan_protections

    # Risk variants first so they win the (name, tagger) dedup in
    # Endpoint#add_tag — a reviewer should see "permissive CORS", not
    # "CORS configured", when both touch the same endpoint. The tag and
    # description are tie-breakers: `sort_by!` is not stable, so without
    # them two same-tag, same-risk protections (e.g. an `X-Frame-Options`
    # and a `Content-Security-Policy` line both → `security-headers`)
    # could surface a different description run-to-run, making scan
    # output non-deterministic.
    @protections.sort_by! { |p| {p.risk ? 0 : 1, p.tag, p.description} }

    super
  end

  private def pre_scan_protections
    @protections.clear

    collect_files_by_extension(".rs").each do |file|
      next if test_path?(file)
      content = read_file(file)
      next if content.nil?
      scan_rust_source(content)
    end

    # Loco (and similar) configure middleware in YAML, not code.
    (collect_files_by_extension(".yaml") + collect_files_by_extension(".yml")).uniq!.each do |file|
      next unless file.includes?("/config/")
      content = read_file(file)
      next if content.nil?
      scan_loco_config(content)
    end

    @protections.uniq!
  end

  # Integration tests / benches / examples define throwaway apps whose
  # middleware must not leak onto real endpoints.
  #
  # Scan-base-relative, never absolute: a `tests/` directory above the
  # scan base belongs to whatever the checkout sits in, and matching it
  # skipped the whole middleware pre-scan.
  private def test_path?(path : String) : Bool
    relative = base_relative_path(path)
    relative.includes?("/tests/") ||
      relative.includes?("/benches/") ||
      relative.includes?("/examples/")
  end

  private def scan_rust_source(content : String)
    lines = content.split("\n")
    imports, layers = syntax_spans(content)

    # `#[cfg(test)]` module skipping via brace depth.
    brace_depth = 0
    in_test = false
    test_base = 0
    pending_test = false

    lines.each_with_index do |line, idx|
      stripped = line.strip

      if stripped.matches?(/#\[cfg\([^)]*\btest\b[^)]*\)\]/)
        pending_test = true
      end

      opens = count_char(stripped, '{')
      closes = count_char(stripped, '}')

      if pending_test && stripped.includes?("{")
        in_test = true
        test_base = brace_depth
        pending_test = false
      end

      unless in_test || stripped.starts_with?("//") || imports.includes?(idx)
        detect_line_protections(lines, idx, stripped, layers)
      end

      brace_depth += opens - closes
      if in_test && brace_depth <= test_base
        in_test = false
      end
    end
  end

  # Rows of `use` declarations (naming a layer type applies nothing) and
  # the axum `.layer(..)` calls of the file.
  private def syntax_spans(content : String) : {Set(Int32), Array(LayerSpan)}
    rows = Set(Int32).new
    layers = [] of LayerSpan
    return {rows, layers} unless content.matches?(ANY_PATTERN)
    Noir::TreeSitter.parse_rust(content) do |root|
      Noir::TreeSitter.walk(root) do |node|
        case Noir::TreeSitter.node_type(node)
        when "use_declaration"
          (Noir::TreeSitter.node_start_row(node)..Noir::TreeSitter.node_end_row(node)).each { |row| rows << row }
        when "call_expression"
          next unless {"layer", "route_layer"}.includes?(field_call_name(node, content))
          args = Noir::TreeSitter.field(node, "arguments") || next
          scope = layer_scope(node, content) || next
          layers << LayerSpan.new(Noir::TreeSitter.node_start_row(args), Noir::TreeSitter.node_end_row(args), scope)
        end
      end
    end
    {rows, layers}
  end

  # What `recv.layer(..)` wraps. axum applies a layer only to the routes
  # registered before it: `.route("/p", get(h).layer(x))` wraps that route,
  # a `Router::new()` chain the routes it reads, and an unread receiver
  # every route but the ones chained after the layer. A tower
  # `ServiceBuilder` layer is not a router's; the router layer it is handed
  # to decides.
  private def layer_scope(call : LibTreeSitter::TSNode, source : String) : Scope?
    if route = find_enclosing_route_call(call, source)
      path = named_call_args(route)[0]?.try { |arg| string_literal_content(arg, source) }
      return path ? Scope.new("/", [{"route", path}]) : nil
    end
    root = call
    while (recv = chain_receiver(root)) && Noir::TreeSitter.node_type(recv) == "call_expression"
      root = recv
    end
    return if call_func_full_text(root, source).ends_with?("ServiceBuilder::new")
    if mounts = router_mounts(call, source)
      return Scope.new("/", mounts)
    end
    Scope.new("/", nil, routes_chained_after(call, source))
  end

  ROUTER_NEW = /\bRouter(?:::<[^<>]*>)?::new\z/

  # The routes and nests of the `Router::new()` chain read before `call`;
  # nil when the chain holds anything else (a merge, a variable, a path
  # that is not a literal).
  private def router_mounts(call : LibTreeSitter::TSNode, source : String) : Array({String, String})?
    mounts = [] of {String, String}
    cursor = chain_receiver(call)
    while cur = cursor
      return unless Noir::TreeSitter.node_type(cur) == "call_expression"
      case name = field_call_name(cur, source)
      when nil
        return unless call_func_full_text(cur, source).matches?(ROUTER_NEW)
        return mounts.empty? ? nil : mounts
      when "route", "nest", "nest_service"
        path = named_call_args(cur)[0]?.try { |arg| string_literal_content(arg, source) }
        return unless path
        mounts << {name == "route" ? "route" : "nest", path}
      when "merge"
        return
      end
      cursor = chain_receiver(cur)
    end
    nil
  end

  # Literal paths of the `.route(..)` calls chained onto `call`.
  private def routes_chained_after(call : LibTreeSitter::TSNode, source : String) : Array(String)
    paths = [] of String
    node = call
    while (field = Noir::TreeSitter.parent(node)) && Noir::TreeSitter.node_type(field) == "field_expression"
      outer = Noir::TreeSitter.parent(field) || break
      break unless Noir::TreeSitter.node_type(outer) == "call_expression"
      if field_call_name(outer, source) == "route"
        named_call_args(outer)[0]?.try { |arg| string_literal_content(arg, source) }.try { |path| paths << path }
      end
      node = outer
    end
    paths
  end

  private def detect_line_protections(lines : Array(String), idx : Int32, stripped : String, layers : Array(LayerSpan))
    # `scope_at` is only invoked from a branch that already matched, so the
    # walk-up cost is paid solely on middleware lines.

    # CORS — permissive wins over a generic "present" match on the same line.
    if m = match_first(stripped, CORS_PERMISSIVE_PATTERNS)
      add_protection("cors", scope_at(lines, idx, layers), true,
        "Permissive CORS (#{m}) — cross-origin requests are accepted from any origin, so any website can read responses to credentialed requests. Confirm this is intended for the endpoints it covers.")
    elsif m = match_first(stripped, CORS_PRESENT_PATTERNS)
      add_protection("cors", scope_at(lines, idx, layers), false,
        "CORS configured (#{m}) — cross-origin access is restricted to an explicit origin allow-list.")
    end

    if m = match_first(stripped, RATE_LIMIT_PATTERNS)
      add_protection("rate-limit", scope_at(lines, idx, layers), false,
        "Rate limited (#{m}) — request volume to this endpoint is throttled per client, mitigating brute-force and abuse.")
    end

    if m = match_first(stripped, SECURITY_HEADER_PATTERNS)
      add_protection("security-headers", scope_at(lines, idx, layers), false,
        "Security response header set (#{m}) — the response is hardened against clickjacking / MIME-sniffing / protocol-downgrade attacks.")
    end

    if m = match_first(stripped, BODY_LIMIT_DISABLED_PATTERNS)
      add_protection("body-limit", scope_at(lines, idx, layers), true,
        "Request body size limit disabled (#{m}) — unbounded request bodies are accepted, a memory-exhaustion denial-of-service risk.")
    elsif m = match_first(stripped, BODY_LIMIT_PATTERNS)
      add_protection("body-limit", scope_at(lines, idx, layers), false,
        "Request body size limited (#{m}) — oversized request bodies are rejected, mitigating memory-exhaustion DoS.")
    end
  end

  # Loco's `config/*.yaml` `server.middlewares:` block. Each protection
  # is app-wide (prefix `/`).
  private def scan_loco_config(content : String)
    lines = content.split("\n")

    lines.each_with_index do |line, idx|
      next if line.lstrip.starts_with?("#")
      key = line.match(/^(\s*)(cors|limit_payload|secure_headers):\s*$/)
      next if key.nil?

      indent = key[1].size
      kind = key[2]
      block = collect_yaml_block(lines, idx, indent)

      # An explicit `enable: false` means the middleware is off — skip.
      next if block.any?(&.matches?(/\benable:\s*false\b/))

      case kind
      when "cors"
        if loco_cors_permissive?(block)
          add_protection("cors", APP_WIDE, true,
            "Permissive CORS (Loco config allow_origins: \"*\") — cross-origin requests are accepted from any origin.")
        else
          add_protection("cors", APP_WIDE, false,
            "CORS configured (Loco middleware) — cross-origin access is governed by the Loco CORS middleware.")
        end
      when "limit_payload"
        add_protection("body-limit", APP_WIDE, false,
          "Request body size limited (Loco limit_payload middleware) — oversized request bodies are rejected.")
      when "secure_headers"
        add_protection("security-headers", APP_WIDE, false,
          "Security response headers set (Loco secure_headers middleware) — responses carry hardening headers (CSP, X-Frame-Options, …).")
      end
    end
  end

  # A Loco `cors:` block is permissive when its origin list is (or
  # contains) `*` — either an inline `allow_origins: ["*"]` or a `- "*"`
  # list item.
  private def loco_cors_permissive?(block : Array(String)) : Bool
    block.any? do |line|
      line.matches?(/allow_origins:\s*\[?\s*["']?\*/) ||
        line.matches?(/^-\s*["']?\*["']?\s*$/)
    end
  end

  # Gather a YAML mapping value's nested lines (those indented deeper than
  # the key) as stripped strings for cheap per-line checks.
  private def collect_yaml_block(lines : Array(String), key_idx : Int32, key_indent : Int32) : Array(String)
    buf = [] of String
    idx = key_idx + 1
    while idx < lines.size
      line = lines[idx]
      stripped = line.strip
      if stripped.empty?
        idx += 1
        next
      end
      indent = line.size - line.lstrip.size
      break if indent <= key_indent
      buf << stripped
      idx += 1
    end
    buf
  end

  # Walk upward from a middleware call to the nearest enclosing Actix
  # `web::scope("/x")`, or `/` when the call sits on an app/router head.
  # A found scope always wins; otherwise we fall back to `/`.
  # An axum `.layer(..)` never gets here: `layer_scope` reads what it wraps.
  private def resolve_chain_prefix(lines : Array(String), idx : Int32) : String
    i = idx
    steps = 0
    while i >= 0 && steps <= 25
      s = lines[i].strip

      if m = s.match(/web::(?:scope|resource)\s*\(\s*"([^"]*)"/)
        return normalize_prefix(m[1])
      end

      if s.includes?("App::new(") || s.includes?("Router::new(") ||
         s.includes?("HttpServer::new(") || s.matches?(/\bcfg\.service\s*\(/) ||
         s.includes?("ServiceConfig")
        return "/"
      end

      i -= 1
      steps += 1
    end

    "/"
  end

  private def normalize_prefix(raw : String) : String
    p = raw.strip
    return "/" if p.empty? || p == "/"
    p = "/" + p unless p.starts_with?("/")
    p = p.rstrip("/")
    p.empty? ? "/" : p
  end

  private def match_first(line : String, patterns : Array(Tuple(Regex, String))) : String?
    patterns.each do |pattern, label|
      return label if line.matches?(pattern)
    end
    nil
  end

  APP_WIDE = Scope.new("/")

  # The innermost axum `.layer(..)` whose arguments hold the line decides;
  # any other line falls back to the enclosing scope or the app.
  private def scope_at(lines : Array(String), idx : Int32, layers : Array(LayerSpan)) : Scope
    layer = layers.select { |span| span.first <= idx && idx <= span.last }.min_by? { |span| span.last - span.first }
    layer ? layer.scope : Scope.new(resolve_chain_prefix(lines, idx))
  end

  private def add_protection(tag : String, scope : Scope, risk : Bool, description : String)
    @protections << Protection.new(tag, description, scope, risk)
  end

  private def count_char(str : String, char : Char) : Int32
    str.count(char)
  end

  private def check_endpoint(endpoint : Endpoint)
    url = endpoint.url
    @protections.each do |protection|
      next unless covers?(protection.scope, url)
      endpoint.add_tag(Tag.new(protection.tag, protection.description, "rust_security"))
    end
  end

  # A router-local path also covers itself under a `nest` prefix, so
  # `/files` covers `/api/files`.
  private def covers?(scope : Scope, url : String) : Bool
    if mounts = scope.mounts
      return mounts.any? do |(kind, path)|
        if kind == "nest"
          url_under_prefix?(url, path) || url.includes?("#{path.rstrip('/')}/")
        else
          url == path || (path.size > 1 && url.ends_with?(path))
        end
      end
    end
    url_under_prefix?(url, scope.prefix) && scope.except.none? { |path| url == path || (path.size > 1 && url.ends_with?(path)) }
  end

  # `/` (or empty) matches everything. Otherwise require a real path
  # boundary so `/api` does not match `/apiv2`.
  private def url_under_prefix?(url : String, prefix : String) : Bool
    return true if prefix == "/" || prefix.empty?
    return true if url == prefix
    boundary = prefix.ends_with?("/") ? prefix : prefix + "/"
    url.starts_with?(boundary)
  end
end
