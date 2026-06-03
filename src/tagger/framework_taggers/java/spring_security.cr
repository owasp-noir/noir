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
#     request by default; an explicit `csrf().disable()`,
#     `csrf(AbstractHttpConfigurer::disable)` or Kotlin `csrf { disable() }`
#     in a SecurityFilterChain turns that off. We flag the state-changing
#     endpoints (POST/PUT/PATCH/DELETE) the affected filter chain exposes.
#     Disabling CSRF is common and often intentional for token/stateless
#     REST APIs, but it is always worth surfacing for review.
#   * cors — a `@CrossOrigin` annotation on the handler or its controller
#     opts the endpoint out of the browser same-origin default. Wildcard
#     origins (`*`), and especially a wildcard combined with credentials,
#     are called out as permissive.
#   * input-validation — `@Valid` / `@Validated` on the handler applies Bean
#     Validation to the request payload, the primary Spring input-validation
#     control. Surfacing where it IS applied also makes the gaps — handlers
#     taking a body without it — visible by their absence.
#
# CSRF is detected from the security config (pre-scanned once, like
# spring_auth's URL rules). CORS and input-validation are per-endpoint and
# line-based, walking the handler the endpoint maps to. Cross-file concerns
# (a custom Filter bean, a global CorsConfigurationSource) are out of scope.
class SpringSecurityTagger < FrameworkTagger
  STATE_CHANGING_METHODS = Set{"POST", "PUT", "PATCH", "DELETE"}

  # A SecurityFilterChain bean / WebSecurityConfigurerAdapter.configure body
  # delimits one HttpSecurity scope. A CSRF-disable and any chain-level
  # securityMatcher are associated within the same scope/block.
  SCOPE_BOUNDARY = /SecurityFilterChain\b|configure\s*\(\s*(?:final\s+)?HttpSecurity/

  # `csrf().disable()` (fluent), `csrf(csrf -> csrf.disable())` /
  # `csrf(AbstractHttpConfigurer::disable)` (lambda/method-ref), and Kotlin
  # `csrf { disable() }`.
  CSRF_DISABLE = /csrf\s*(?:\(\s*\)\s*\.\s*disable\b|\([^)]*\bdisable|\{[^}]*\bdisable)/

  # Chain-level request matchers that scope a SecurityFilterChain to a URL
  # subset. `requestMatchers(...)` is deliberately excluded: inside
  # `authorizeHttpRequests {…}` it scopes an authorization rule, not the
  # chain, and treating those as CSRF scopes would mis-attribute the rule.
  MATCHER_CALL = /\b(?:securityMatcher|antMatcher)\s*\(/

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "spring_security"
    @csrf_disable_scopes = [] of String
  end

  def self.target_techs : Array(String)
    ["java_spring", "kotlin_spring"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    pre_scan_csrf_config
    endpoints.each { |endpoint| check_endpoint(endpoint) }
    endpoints
  end

  # ---- CSRF (config-level) ---------------------------------------------

  private def pre_scan_csrf_config
    @csrf_disable_scopes.clear
    [".java", ".kt"].each do |ext|
      collect_files_by_extension(ext).each do |file|
        content = read_file(file)
        next if content.nil?
        next unless content.includes?("HttpSecurity") || content.includes?("SecurityFilterChain") || content.includes?("WebSecurityConfigurerAdapter")
        scan_csrf_config(content)
      end
    end
    @csrf_disable_scopes.uniq!
  end

  private def scan_csrf_config(content : String)
    split_into_chain_blocks(content).each do |block|
      next unless block.matches?(CSRF_DISABLE)

      matchers = extract_matchers(block)
      if matchers.size > 0
        # CSRF disabled for a chain scoped to these URL pattern(s).
        matchers.each { |m| @csrf_disable_scopes << m }
      elsif !block.matches?(MATCHER_CALL)
        # No matcher at all → this chain (and its CSRF-disable) is global.
        @csrf_disable_scopes << "/**"
      end
      # else: scoped by a non-literal matcher (e.g. EndpointRequest) we
      # cannot resolve to a URL — skip rather than over-broaden to global.
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

  private def csrf_disabled_scope_for(endpoint : Endpoint) : String?
    return unless STATE_CHANGING_METHODS.includes?(endpoint.method.upcase)
    @csrf_disable_scopes.find { |pattern| matches_ant_pattern?(endpoint.url, pattern) }
  end

  # ---- per-endpoint ----------------------------------------------------

  private def check_endpoint(endpoint : Endpoint)
    if scope = csrf_disabled_scope_for(endpoint)
      desc = if scope == "/**"
               "CSRF protection disabled globally (Spring Security csrf().disable()) — state-changing requests to this endpoint are not CSRF-validated."
             else
               "CSRF protection disabled for the \"#{scope}\" filter chain — state-changing requests to this endpoint are not CSRF-validated."
             end
      endpoint.add_tag(Tag.new("csrf-protection", desc, "spring_security"))
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

      if desc = check_input_validation(lines, idx)
        endpoint.add_tag(Tag.new("input-validation", desc, "spring_security"))
      end
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
  private def check_input_validation(lines : Array(String), method_idx : Int32) : String?
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
      idx += 1
    end

    if class_level_annotation(lines, "@Validated")
      return "Controller annotated @Validated — Bean Validation is applied to this handler's parameters."
    end

    nil
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
    regex_str = pattern.gsub("**", "DOUBLE_STAR")
      .gsub("*", "[^/]*")
      .gsub("DOUBLE_STAR", ".*")
    url.matches?(/^#{regex_str}/)
  rescue ex
    @logger.debug "SpringSecurityTagger: failed to match ant pattern '#{pattern}': #{ex.message}"
    false
  end
end
