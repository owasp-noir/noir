require "../../../models/framework_tagger"
require "../../../models/endpoint"

# Spring-specific security tagger.
#
# `spring_auth` already classifies authentication/authorization
# (@PreAuthorize/@Secured/@RolesAllowed annotations and HttpSecurity URL
# rules). This tagger covers the *other* Spring security signals a reviewer
# cares about — the protections Spring ships and the deviations from its
# secure defaults — that map cleanly onto an endpoint:
#
#   * csrf-protection — Spring Security CSRF-protects every state-changing
#     request by default. We flag the state-changing endpoints
#     (POST/PUT/PATCH/DELETE) where that is turned off, either wholesale for
#     a filter chain (`csrf().disable()`, `csrf(AbstractHttpConfigurer::disable)`,
#     Kotlin `csrf { disable() }`) or selectively for specific paths
#     (`csrf(c -> c.ignoringRequestMatchers("/api/**"))`). Common and often
#     intentional for token/stateless APIs, but always worth surfacing.
#   * cors — a `@CrossOrigin` annotation on the handler/controller, or a
#     global `WebMvcConfigurer` CORS mapping (`addMapping(...).allowedOrigins("*")`),
#     opts the endpoint out of the browser same-origin default. Wildcard
#     origins (`*`), especially combined with credentials, are permissive.
#   * security-headers — Spring Security adds a sensible default header set
#     (X-Frame-Options DENY, X-Content-Type-Options, Cache-Control, …). We
#     flag the endpoints where those are weakened: clickjacking protection
#     off (`frameOptions().disable()`) or the whole header writer disabled
#     (`headers().disable()` / `headers(HeadersConfigurer::disable)`).
#   * input-validation — `@Valid` / `@Validated` on the handler applies Bean
#     Validation to the request payload, the primary Spring input-validation
#     control. Surfacing where it IS applied also makes the gaps — handlers
#     taking a body without it — visible by their absence.
#
# CSRF / security-headers / config CORS are detected from the security,
# MVC, and WebSocket config (pre-scanned once, like spring_auth's URL rules). The
# `@CrossOrigin` and input-validation signals are per-endpoint, line-based
# walks of the handler the endpoint maps to. Cross-file concerns (a custom
# Filter bean, a bespoke CorsConfigurationSource) are out of scope.
class SpringSecurityTagger < FrameworkTagger
  STATE_CHANGING_METHODS = Set{"POST", "PUT", "PATCH", "DELETE"}

  # A SecurityFilterChain bean / WebSecurityConfigurerAdapter.configure body
  # delimits one HttpSecurity scope. A CSRF-disable and any chain-level
  # securityMatcher are associated within the same scope/block.
  SCOPE_BOUNDARY = /SecurityFilterChain\b|configure\s*\(\s*(?:final\s+)?HttpSecurity/

  # `csrf().disable()` (fluent), `csrf(csrf -> csrf.disable())` /
  # `csrf(AbstractHttpConfigurer::disable)` (lambda/method-ref), and Kotlin
  # `csrf { disable() }`. Whole-chain disable.
  CSRF_DISABLE = /csrf\s*(?:\(\s*\)\s*\.\s*disable\b|\([^)]*\bdisable|\{[^}]*\bdisable)/

  # `ignoringRequestMatchers(...)` / `ignoringAntMatchers(...)` — CSRF kept on
  # for the chain but skipped for these (absolute) path patterns. Captured
  # across line breaks: the arg group stops at the statement's `;`, never
  # crossing into the next statement. The inner quote scan pulls the path
  # literal even when wrapped (e.g. `new AntPathRequestMatcher("/api")`).
  IGNORING_ARGS = /(?:ignoringRequestMatchers|ignoringAntMatchers)\s*\(([^;]*?)\)/

  # Clickjacking protection off: `frameOptions().disable()`,
  # `frameOptions(f -> f.disable())`, Kotlin `frameOptions { disable() }`.
  FRAME_OPTIONS_DISABLE = /frameOptions\s*(?:\(\s*\)\s*\.\s*disable\b|\([^)]*\bdisable|\{[^}]*\bdisable)/

  # Whole default header writer off. Restricted to the unambiguous forms —
  # empty-paren fluent `headers().disable()` and the method-ref
  # `headers(HeadersConfigurer::disable)` — so a *nested* per-header disable
  # such as `headers(h -> h.frameOptions(f -> f.disable()))` is NOT mistaken
  # for an all-headers-off (that one is caught by FRAME_OPTIONS_DISABLE).
  HEADERS_FULLY_DISABLED = /headers\s*(?:\(\s*\)\s*\.\s*disable\b|\([^)]*::\s*disable)/

  # Chain-level request matchers that scope a SecurityFilterChain to a URL
  # subset. `requestMatchers(...)` is deliberately excluded: inside
  # `authorizeHttpRequests {…}` it scopes an authorization rule, not the
  # chain, and treating those as CSRF scopes would mis-attribute the rule.
  MATCHER_CALL = /\b(?:securityMatcher|antMatcher)\s*\(/

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "spring_security"
    @csrf_disable_scopes = [] of String
    @csrf_ignored_scopes = [] of String
    @header_weak_scopes = [] of NamedTuple(pattern: String, kind: Symbol)
    @cors_config_scopes = [] of NamedTuple(pattern: String, credentials: Bool, source: Symbol)
  end

  def self.target_techs : Array(String)
    ["java_spring", "kotlin_spring"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    pre_scan_config
    endpoints.each { |endpoint| check_endpoint(endpoint) }
    endpoints
  end

  # ---- config pre-scan -------------------------------------------------

  private def pre_scan_config
    @csrf_disable_scopes.clear
    @csrf_ignored_scopes.clear
    @header_weak_scopes.clear
    @cors_config_scopes.clear

    [".java", ".kt"].each do |ext|
      collect_files_by_extension(ext).each do |file|
        content = read_file(file)
        next if content.nil?

        if content.includes?("HttpSecurity") || content.includes?("SecurityFilterChain") || content.includes?("WebSecurityConfigurerAdapter")
          scan_security_config(content)
        end
        scan_cors_mappings(content) if content.includes?(".addMapping")
        scan_websocket_cors_endpoints(content) if content.includes?(".addEndpoint")
      end
    end

    @csrf_disable_scopes.uniq!
    @csrf_ignored_scopes.uniq!
    @header_weak_scopes.uniq!
    @cors_config_scopes.uniq!
  end

  private def scan_security_config(content : String)
    split_into_chain_blocks(content).each do |block|
      matchers = extract_matchers(block)

      # (a) Whole-chain CSRF disable.
      record_scoped(@csrf_disable_scopes, matchers, block) if block.matches?(CSRF_DISABLE)

      # (b) CSRF skipped for specific (absolute) paths. Used directly — these
      #     matchers are not relative to the chain's securityMatcher.
      extract_ignoring_matchers(block).each { |p| @csrf_ignored_scopes << p }

      # (c) Default security response headers weakened. Whole-writer-off wins
      #     over the frameOptions-only case when both somehow appear.
      if block.matches?(HEADERS_FULLY_DISABLED)
        record_header_scope(:all, matchers, block)
      elsif block.matches?(FRAME_OPTIONS_DISABLE)
        record_header_scope(:frame, matchers, block)
      end
    end
  end

  # Record a chain-scoped rule: scope to the chain's securityMatcher pattern(s)
  # when present; treat a matcher-less chain as global `/**`; skip a chain
  # scoped only by a non-literal matcher (e.g. EndpointRequest) we can't
  # resolve, rather than over-broadening it to global.
  private def record_scoped(target : Array(String), matchers : Array(String), block : String)
    if matchers.size > 0
      matchers.each { |m| target << m }
    elsif !block.matches?(MATCHER_CALL)
      target << "/**"
    end
  end

  private def record_header_scope(kind : Symbol, matchers : Array(String), block : String)
    if matchers.size > 0
      matchers.each { |m| @header_weak_scopes << {pattern: m, kind: kind} }
    elsif !block.matches?(MATCHER_CALL)
      @header_weak_scopes << {pattern: "/**", kind: kind}
    end
  end

  # Split a config file into one block per HttpSecurity scope so a
  # CSRF-disable is associated only with its own filter chain's matcher.
  private def split_into_chain_blocks(content : String) : Array(String)
    blocks = [] of String
    current = [] of String
    content.each_line do |raw|
      if raw.matches?(SCOPE_BOUNDARY) && !current.empty?
        blocks << current.join("\n")
        current = [] of String
      end
      current << raw
    end
    blocks << current.join("\n") unless current.empty?
    blocks
  end

  private def extract_matchers(block : String) : Array(String)
    matchers = [] of String
    block.each_line do |raw|
      next unless raw.matches?(MATCHER_CALL)
      raw.scan(/"([^"]+)"/) { |m| matchers << m[1] }
    end
    matchers
  end

  private def extract_ignoring_matchers(block : String) : Array(String)
    result = [] of String
    block.scan(IGNORING_ARGS) do |m|
      m[1].scan(/"([^"]+)"/) { |q| result << q[1] }
    end
    result
  end

  # `addMapping("/x").allowedOrigins("*")...` in a WebMvcConfigurer. Only a
  # wildcard origin is permissive enough to flag: a mapping listing specific
  # origins is the intended, safe use of CORS.
  private def scan_cors_mappings(content : String)
    fluent_call_statements(content, ".addMapping").each do |stmt|
      m = stmt.match(/\.addMapping\s*\(([^)]*)\)/)
      next unless m

      next unless wildcard_origin_call?(stmt, ["allowedOrigins", "allowedOriginPatterns"])

      credentials = stmt.includes?("allowCredentials") && stmt.includes?("true")
      quoted_literals(m[1]).each do |pattern|
        @cors_config_scopes << {pattern: pattern, credentials: credentials, source: :mvc}
      end
    end
  end

  # `addEndpoint("/ws").setAllowedOrigins("*")...` in a STOMP/WebSocket
  # config controls the HTTP handshake endpoint. Treat wildcard origins here
  # as the same cross-origin exposure reviewers expect to see on REST routes.
  private def scan_websocket_cors_endpoints(content : String)
    fluent_call_statements(content, ".addEndpoint").each do |stmt|
      m = stmt.match(/\.addEndpoint\s*\(([^)]*)\)/)
      next unless m

      next unless wildcard_origin_call?(stmt, ["setAllowedOrigins", "setAllowedOriginPatterns"])

      quoted_literals(m[1]).each do |pattern|
        @cors_config_scopes << {pattern: pattern, credentials: false, source: :websocket}
      end
    end
  end

  private def fluent_call_statements(content : String, call_name : String) : Array(String)
    lines = content.lines
    statements = [] of String

    lines.each_with_index do |line, idx|
      next unless line.includes?(call_name)

      stmt_lines = [line]
      next_idx = idx + 1
      while next_idx < lines.size && stmt_lines.size < 8
        stripped = lines[next_idx].strip
        break if stripped.empty?
        break if stripped.starts_with?("}") || stripped.matches?(/^(override|fun|class|public|private|protected|internal|return)\b/)
        break unless stripped.starts_with?(".") || stripped.includes?("allowedOrigin") || stripped.includes?("allowCredentials")

        stmt_lines << lines[next_idx]
        break if stripped.includes?(";")
        next_idx += 1
      end

      statements << stmt_lines.join
    end

    statements
  end

  # Call-name and ant-pattern regexes interpolate low-cardinality dynamic
  # strings; memoize them so per-statement / per-URL checks don't
  # recompile a PCRE2 pattern each time.
  @origin_call_regexes = Hash(String, Regex).new
  @ant_pattern_regexes = Hash(String, Regex).new

  private def wildcard_origin_call?(stmt : String, call_names : Array(String)) : Bool
    call_names.any? do |call_name|
      call_re = @origin_call_regexes[call_name] ||= /#{Regex.escape(call_name)}\s*\(([^)]*)\)/
      wildcard = false
      stmt.scan(call_re) do |m|
        args = m[1]
        wildcard = true if args.includes?("\"*\"") || args.includes?("'*'")
      end
      wildcard
    end
  end

  private def quoted_literals(args : String) : Array(String)
    result = [] of String
    args.scan(/"([^"]+)"/) { |m| result << m[1] }
    result
  end

  # ---- per-endpoint resolution ----------------------------------------

  private def csrf_disabled_description_for(endpoint : Endpoint) : String?
    return unless STATE_CHANGING_METHODS.includes?(endpoint.method.upcase)
    url = endpoint.url

    # Specific ignored paths first — more precise than a chain-wide disable.
    if scope = @csrf_ignored_scopes.find { |p| matches_ant_pattern?(url, p) }
      return "CSRF protection disabled for paths matching \"#{scope}\" (csrf ignoringRequestMatchers) — state-changing requests here are not CSRF-validated."
    end

    if scope = @csrf_disable_scopes.find { |p| matches_ant_pattern?(url, p) }
      return scope == "/**" ? "CSRF protection disabled globally (Spring Security csrf().disable()) — state-changing requests to this endpoint are not CSRF-validated." : "CSRF protection disabled for the \"#{scope}\" filter chain — state-changing requests to this endpoint are not CSRF-validated."
    end

    nil
  end

  private def security_headers_description_for(endpoint : Endpoint) : String?
    rule = @header_weak_scopes.find { |r| matches_ant_pattern?(endpoint.url, r[:pattern]) }
    return unless rule

    if rule[:kind] == :all
      "Spring Security default response headers disabled for this endpoint (headers().disable()) — clickjacking (X-Frame-Options), MIME-sniffing (X-Content-Type-Options) and cache-control protections are all off."
    else
      "Clickjacking protection disabled for this endpoint — X-Frame-Options is turned off (frameOptions().disable()), so responses can be embedded in a frame by any site."
    end
  end

  private def cors_config_description_for(endpoint : Endpoint) : String?
    rule = @cors_config_scopes.find { |r| matches_ant_pattern?(endpoint.url, r[:pattern]) }
    return unless rule

    call_name = rule[:source] == :websocket ? "addEndpoint" : "addMapping"
    source = rule[:source] == :websocket ? "WebSocket/STOMP endpoint config" : "global WebMvc config"

    if rule[:credentials]
      "Permissive CORS (#{source}) — #{call_name}(\"#{rule[:pattern]}\") allows all origins (*) with credentials, exposing authenticated responses cross-origin."
    else
      "Permissive CORS (#{source}) — #{call_name}(\"#{rule[:pattern]}\") allows all origins (*)."
    end
  end

  # ---- per-endpoint ----------------------------------------------------

  private def check_endpoint(endpoint : Endpoint)
    if desc = csrf_disabled_description_for(endpoint)
      endpoint.add_tag(Tag.new("csrf-protection", desc, "spring_security"))
    end

    if desc = security_headers_description_for(endpoint)
      endpoint.add_tag(Tag.new("security-headers", desc, "spring_security"))
    end

    read_source_context(endpoint).each do |ctx|
      line = ctx.line
      next if line.nil?
      lines = ctx.full_content.split("\n")
      next if line < 1 || line > lines.size
      idx = line - 1

      if desc = check_cross_origin(lines, idx)
        endpoint.add_tag(Tag.new("cors", desc, "spring_security"))
      end

      if desc = check_input_validation(lines, idx, endpoint)
        endpoint.add_tag(Tag.new("input-validation", desc, "spring_security"))
      end
    end

    # Config-based CORS is annotation-independent. add_tag dedups by
    # (name, tagger), so an endpoint already tagged from a @CrossOrigin
    # annotation keeps that (more specific) description.
    if desc = cors_config_description_for(endpoint)
      endpoint.add_tag(Tag.new("cors", desc, "spring_security"))
    end
  end

  # `@CrossOrigin` on the handler (walk the annotation block above it) or on
  # the controller class (applies to every handler in the file).
  private def check_cross_origin(lines : Array(String), method_idx : Int32) : String?
    # Method-level: the contiguous annotation block directly above the
    # handler. Mirrors spring_auth's backward walk — stop at the previous
    # member/class boundary so we don't bleed into another handler.
    idx = method_idx - 1
    while idx >= 0 && idx >= method_idx - 15
      current = lines[idx].strip
      if current.empty?
        idx -= 1
        next
      end
      break if current.starts_with?("public ") || current.starts_with?("private ") || current.starts_with?("protected ")
      break if current.starts_with?("class ") || current.starts_with?("}") || current.ends_with?("}")

      return describe_cross_origin(current) if current.includes?("@CrossOrigin")
      idx -= 1
    end

    # Class-level: a @CrossOrigin sitting on the controller declaration.
    if class_line = class_level_annotation(lines, "@CrossOrigin")
      return describe_cross_origin(class_line, class_level: true)
    end

    nil
  end

  private def describe_cross_origin(line : String, class_level : Bool = false) : String
    scope = class_level ? "controller" : "handler"
    # No parenthesised args → Spring's @CrossOrigin defaults to allowing all
    # origins.
    unless line.includes?("(")
      return "Cross-origin requests enabled on this #{scope} via @CrossOrigin with no origin restriction (defaults to allowing all origins)."
    end

    wildcard = line.includes?("\"*\"") || line.includes?("'*'")
    credentials = line.includes?("allowCredentials") && line.includes?("true")
    if wildcard && credentials
      "Permissive CORS on this #{scope} — @CrossOrigin allows all origins (*) with credentials, exposing authenticated responses cross-origin."
    elsif wildcard
      "Permissive CORS on this #{scope} — @CrossOrigin allows all origins (*)."
    else
      "Cross-origin requests enabled on this #{scope} via @CrossOrigin."
    end
  end

  # `@Valid` / `@Validated` applied to the handler's parameters (scan the
  # signature up to the body brace) or `@Validated` on the controller class.
  private def check_input_validation(lines : Array(String), method_idx : Int32, endpoint : Endpoint) : String?
    idx = method_idx
    end_idx = [method_idx + 10, lines.size - 1].min
    while idx <= end_idx
      current = lines[idx]
      if current.includes?("@Valid") || current.includes?("@Validated")
        return "Request payload validated by Bean Validation (@Valid/@Validated)."
      end
      # The first body brace closes the signature — stop before scanning the
      # method body so a `@Valid` used deeper inside cannot leak in.
      break if current.includes?("{")
      # Kotlin expression-bodied handlers (`fun list() = service.list()`)
      # have no body brace. Stop if we reach the next route annotation so a
      # following handler's `@Valid` does not bleed into this endpoint.
      break if idx > method_idx && spring_mapping_annotation?(current)
      idx += 1
    end

    if endpoint.params.present? && class_level_annotation(lines, "@Validated")
      return "Controller annotated @Validated — Bean Validation is applied to this handler's parameters."
    end

    nil
  end

  private def spring_mapping_annotation?(line : String) : Bool
    line.matches?(/@(GetMapping|PostMapping|PutMapping|PatchMapping|DeleteMapping|RequestMapping)\b/)
  end

  # Find an annotation (`@CrossOrigin`/`@Validated`) that decorates the class
  # declaration: it must be immediately followed — skipping other annotations
  # and blank lines — by a `class` line. Returns the annotation line text.
  private def class_level_annotation(lines : Array(String), annotation_name : String) : String?
    lines.each_with_index do |raw, i|
      stripped = raw.strip
      next unless stripped.starts_with?(annotation_name)
      j = i + 1
      while j < lines.size
        nxt = lines[j].strip
        if nxt.empty? || nxt.starts_with?("@")
          j += 1
          next
        end
        return stripped if nxt.includes?("class ")
        break
      end
    end
    nil
  end

  # Ant-style pattern match (`/**` → any depth, `*` → one segment), prefix
  # anchored like spring_auth so `/api/**` matches `/api/posts/1`.
  private def matches_ant_pattern?(url : String, pattern : String) : Bool
    ant_re = @ant_pattern_regexes[pattern] ||= begin
      regex_str = pattern.gsub("**", "DOUBLE_STAR")
        .gsub("*", "[^/]*")
        .gsub("DOUBLE_STAR", ".*")
      /^#{regex_str}/
    end
    url.matches?(ant_re)
  rescue ex
    @logger.debug "SpringSecurityTagger: failed to match ant pattern '#{pattern}': #{ex.message}"
    false
  end
end
