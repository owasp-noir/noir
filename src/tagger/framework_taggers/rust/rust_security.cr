require "../../../models/framework_tagger"
require "../../../models/endpoint"

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
#      middleware (`App::new().wrap(..)`, `Router::new().layer(..)`)
#      maps to `/` so it tags every endpoint. Test modules
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
class RustSecurityTagger < FrameworkTagger
  # A single detected protection: the tag to emit, its human description,
  # the URL prefix it guards, and whether it is a risk (risk variants win
  # dedup so the reviewer sees the alarming description, not the benign).
  record Protection,
    tag : String,
    description : String,
    prefix : String,
    risk : Bool

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

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "rust_security"
    @protections = [] of Protection
  end

  # Kept in lock-step with `rust_auth` (the guard-support invariant in
  # techs_spec requires every framework-tagger target to be a
  # guard-supported tech, which currently excludes Salvo/Poem).
  def self.target_techs : Array(String)
    [
      "rust_axum", "rust_rocket", "rust_actix_web",
      "rust_loco", "rust_rwf", "rust_tide",
      "rust_warp", "rust_gotham",
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

    endpoints.each { |endpoint| apply_protections(endpoint) }
    endpoints
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
  private def test_path?(path : String) : Bool
    path.includes?("/tests/") ||
      path.includes?("/benches/") ||
      path.includes?("/examples/")
  end

  private def scan_rust_source(content : String)
    lines = content.split("\n")

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

      unless in_test || stripped.starts_with?("//")
        detect_line_protections(lines, idx, stripped)
      end

      brace_depth += opens - closes
      if in_test && brace_depth <= test_base
        in_test = false
      end
    end
  end

  private def detect_line_protections(lines : Array(String), idx : Int32, stripped : String)
    # `resolve_chain_prefix` is only invoked from a branch that already
    # matched, so the walk-up cost is paid solely on middleware lines.

    # CORS — permissive wins over a generic "present" match on the same line.
    if m = match_first(stripped, CORS_PERMISSIVE_PATTERNS)
      add_protection("cors", resolve_chain_prefix(lines, idx), true,
        "Permissive CORS (#{m}) — cross-origin requests are accepted from any origin, so any website can read responses to credentialed requests. Confirm this is intended for the endpoints it covers.")
    elsif m = match_first(stripped, CORS_PRESENT_PATTERNS)
      add_protection("cors", resolve_chain_prefix(lines, idx), false,
        "CORS configured (#{m}) — cross-origin access is restricted to an explicit origin allow-list.")
    end

    if m = match_first(stripped, RATE_LIMIT_PATTERNS)
      add_protection("rate-limit", resolve_chain_prefix(lines, idx), false,
        "Rate limited (#{m}) — request volume to this endpoint is throttled per client, mitigating brute-force and abuse.")
    end

    if m = match_first(stripped, SECURITY_HEADER_PATTERNS)
      add_protection("security-headers", resolve_chain_prefix(lines, idx), false,
        "Security response header set (#{m}) — the response is hardened against clickjacking / MIME-sniffing / protocol-downgrade attacks.")
    end

    if m = match_first(stripped, BODY_LIMIT_DISABLED_PATTERNS)
      add_protection("body-limit", resolve_chain_prefix(lines, idx), true,
        "Request body size limit disabled (#{m}) — unbounded request bodies are accepted, a memory-exhaustion denial-of-service risk.")
    elsif m = match_first(stripped, BODY_LIMIT_PATTERNS)
      add_protection("body-limit", resolve_chain_prefix(lines, idx), false,
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
          add_protection("cors", "/", true,
            "Permissive CORS (Loco config allow_origins: \"*\") — cross-origin requests are accepted from any origin.")
        else
          add_protection("cors", "/", false,
            "CORS configured (Loco middleware) — cross-origin access is governed by the Loco CORS middleware.")
        end
      when "limit_payload"
        add_protection("body-limit", "/", false,
          "Request body size limited (Loco limit_payload middleware) — oversized request bodies are rejected.")
      when "secure_headers"
        add_protection("security-headers", "/", false,
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
  #
  # Caveat (Axum/Tower): when a `.layer(..)` is applied to a sub-router
  # that is built in its own statement/function and only later mounted
  # with `nest("/x", sub)`, the walk-up reaches `Router::new(` and
  # resolves `/` — i.e. it tags the whole app even though the layer only
  # covers `/x`. That is a false *positive* (over-broad), unlike the
  # Actix path which errs toward false negatives. We accept it because
  # the alternative (data-flow tracking a router variable across
  # statements) is out of scope for a line-based tagger, and an
  # over-broad "protected" signal is rarer in practice than the inline
  # `Router::new().route(..).layer(..)` form this resolves correctly.
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

  private def add_protection(tag : String, prefix : String, risk : Bool, description : String)
    @protections << Protection.new(tag, description, prefix, risk)
  end

  private def count_char(str : String, char : Char) : Int32
    str.count(char)
  end

  private def apply_protections(endpoint : Endpoint)
    url = endpoint.url
    @protections.each do |protection|
      next unless url_under_prefix?(url, protection.prefix)
      endpoint.add_tag(Tag.new(protection.tag, protection.description, "rust_security"))
    end
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
