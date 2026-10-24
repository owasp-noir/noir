require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../miniparsers/java_route_extractor_ts"
require "../../../utils/js_literal_scanner"
require "../../../utils/top_level_split"

@[Noir::TaggerFor(key: "spring_auth", name: "Spring Auth Tagger", desc: "Identifies Spring Security patterns (annotations, security config)", order: 20)]
class SpringAuthTagger < FrameworkTagger
  ANNOTATION_PATTERNS = [
    /\@PreAuthorize\s*\(/,
    /\@Secured\s*\(/,
    /\@RolesAllowed\s*\(/,
  ]

  # The same authorization annotations, as the bare names they are matched by
  # when they decorate the controller *class* instead of a single handler.
  CLASS_ANNOTATION_NAMES = ["@PreAuthorize", "@Secured", "@RolesAllowed"]

  # Security config URL rules. `access { ... }` is a protected rule too;
  # `permitAll()` is intentionally tracked so a more-specific public matcher
  # can suppress a broader protected one. The matcher's argument list is
  # found by paren matching (it nests `antMatcher(X)` calls and spans lines),
  # so only the call opener is a regex.
  MATCHERS_CALL    = /\.\s*(antMatchers|requestMatchers|mvcMatchers)\s*\(/
  RULE_AFTER_CALL  = /\A\s*\.\s*(permitAll|authenticated|fullyAuthenticated|hasRole|hasAnyRole|hasAuthority|hasAnyAuthority|access)\s*(?:\(|\{)/
  ANY_REQUEST_AUTH = /\.\s*anyRequest\s*\(\s*\)\s*\.\s*(authenticated|fullyAuthenticated|hasRole|hasAnyRole|hasAuthority|hasAnyAuthority|access)\s*(?:\(|\{)/

  # The Kotlin DSL Spring Security documents for Kotlin apps:
  # `authorizeHttpRequests { authorize("/public/**", permitAll);
  # authorize(anyRequest, authenticated) }`.
  KOTLIN_AUTHORIZE_RULE = /\bauthorize\s*\(\s*(?:HttpMethod\.(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s*,\s*)?(?:"([^"]+)"|(anyRequest))\s*,\s*(permitAll|authenticated|fullyAuthenticated|hasRole|hasAnyRole|hasAuthority|hasAnyAuthority|access)\b/

  # A chain is "scoped" when restricted by `securityMatcher(...)`,
  # `securityMatchers(m -> m.requestMatchers(...))` or Spring 5's
  # `http.antMatcher(...)`. The plural `antMatchers(...)` / `requestMatchers(...)`
  # forms are authorization *rules*, and `antMatcher(...)` as a static
  # factory (`requestMatchers(antMatcher("/h2/**"))`,
  # `AntPathRequestMatcher.antMatcher(X)`) builds a rule's matcher — only the
  # HttpSecurity method (`.antMatcher(` on anything but the factory class)
  # scopes the chain.
  SCOPE_MATCHER_CALL = /\b(securityMatchers?)\s*\(|(?<!AntPathRequestMatcher)\.\s*(antMatcher)\s*\(/

  # Calls that build a request matcher from their (pattern) arguments, so
  # `requestMatchers(antMatcher(X))` reads X. Regex matchers are not ant
  # patterns and are deliberately absent.
  MATCHER_FACTORY_CALL = /\A(?:new\s+)?(?:[\w$]+\s*(?:\([^()]*\))?\s*\.\s*)*(?:antMatcher|AntPathRequestMatcher|MvcRequestMatcher|matcher|pattern)\s*\((.*)\)\z/m
  INLINE_STRING_ARRAY  = /\A(?:new\s+String\s*\[\s*\]\s*)?\{(.*)\}\z/m
  JAVA_STRING_LITERAL  = /\A"((?:[^"\\]|\\.)*)"\z/
  CONSTANT_REFERENCE   = /\A[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*\z/
  QUALIFIED_CONSTANT   = /\b([A-Z][\w$]*)\.[A-Z_][A-Z0-9_$]*\b/
  ORDER_ANNOTATION     = /@Order\s*\(\s*(?:value\s*=\s*)?(-?\d+|Ordered\.HIGHEST_PRECEDENCE|Ordered\.LOWEST_PRECEDENCE)\s*\)/
  CHAIN_BOUNDARY       = /SecurityFilterChain\b|configure\s*\(\s*(?:final\s+)?HttpSecurity/

  KOTLIN_FUN_DECLARATION = /(?:^|\s)fun\s/

  alias SecurityRule = NamedTuple(pattern: String, method: String?, description: String, protected_rule: Bool)

  # A `securityMatcher`-scoped SecurityFilterChain: requests its `scope`
  # matches are served by this chain alone (Spring hands a request to the
  # first chain whose matcher matches, and the catch-all chain must come
  # last), so its rules decide them and no other chain's do.
  alias ScopedChain = NamedTuple(scope: Array(String), order: Int32, rules: Array(SecurityRule))

  def initialize(options : Hash(String, YAML::Any))
    super
    # Rules of the chains that serve every request (and of chains scoped by
    # a matcher noir cannot read, which keep the old global treatment).
    @security_rules = [] of SecurityRule
    @scoped_chains = [] of ScopedChain
  end

  def self.target_techs : Array(String)
    ["java_spring", "kotlin_spring"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    # Phase 1: Pre-scan security config files
    pre_scan_security_configs
    super
  end

  private def pre_scan_security_configs
    @security_rules.clear
    @scoped_chains.clear

    # Find Java and Kotlin security config files
    extensions = [".java", ".kt"]
    extensions.each do |ext|
      files = collect_files_by_extension(ext)
      files.each do |file|
        content = read_file(file)
        next if content.nil?
        next unless content.includes?("SecurityFilterChain") || content.includes?("HttpSecurity") || content.includes?("WebSecurityConfigurerAdapter")

        scan_security_config(content, file.ends_with?(".java"))
      end
    end
  end

  private def scan_security_config(content : String, java : Bool)
    strings, arrays = java ? security_constants(content) : {Hash(String, String).new, Hash(String, Array(String)).new}
    split_into_chain_blocks(Noir::CComments.strip(content)).each do |block|
      scan_security_chain(block, strings, arrays)
    end
  end

  # String and `String[]` constants the config can name: its own, plus the
  # ones of every project class it references as `Cls.NAME` or imports
  # statically, read from that class's `Cls.java`.
  private def security_constants(content : String) : {Hash(String, String), Hash(String, Array(String))}
    project = Noir::TreeSitterJavaRouteExtractor::ProjectConstants.new
    project_arrays = Hash(String, Array(String)).new
    referenced = Set(String).new
    content.scan(QUALIFIED_CONSTANT) { |match| referenced << match[1] }
    content.scan(Noir::TreeSitterJavaRouteExtractor::STATIC_IMPORT_NAME_RE) { |match| referenced << match[1].split('.').last }
    referenced.each do |class_name|
      CodeLocator.instance.files_by_basename("#{class_name}.java").each do |file|
        next unless other = read_file(file)
        next unless other.includes?("static") || other.includes?("interface")
        other_strings, other_arrays = Noir::TreeSitterJavaRouteExtractor.extract_string_and_array_constants(other)
        other_strings.each { |name, value| project[name] ||= value if name.includes?('.') }
        other_arrays.each { |name, value| project_arrays[name] ||= value if name.includes?('.') }
      end
    end

    strings, arrays = Noir::TreeSitterJavaRouteExtractor.extract_string_and_array_constants(content, project.empty? ? nil : project)
    project_arrays.each { |name, value| arrays[name] ||= value }
    content.scan(Noir::TreeSitterJavaRouteExtractor::STATIC_IMPORT_NAME_RE) do |match|
      owner, name = match[1], match[2]
      if name == "*"
        project_arrays.each do |key, value|
          next unless key.starts_with?("#{owner}.")
          bare = key[(owner.size + 1)..]
          arrays[bare] ||= value unless bare.includes?('.')
        end
      elsif value = project_arrays["#{owner}.#{name}"]?
        arrays[name] ||= value
      end
    end
    {strings, arrays}
  end

  private def scan_security_chain(block : String, strings : Hash(String, String), arrays : Hash(String, Array(String)))
    scope = chain_scope(block, strings, arrays)
    rules = [] of SecurityRule

    block.scan(MATCHERS_CALL) do |match|
      open = match.byte_end(0) - 1
      next unless close = Noir::JSLiteralScanner.find_matching_paren_at_byte(block, open)
      next unless rule = block.byte_slice(close + 1, 96).match(RULE_AFTER_CALL)

      args = block.byte_slice(open + 1, close - open - 1)
      auth_type = rule[1]
      protected_rule = auth_type != "permitAll"
      matcher_method = request_matcher_method(args)
      matcher_patterns(args, strings, arrays).uniq.each do |url_pattern|
        description =
          if protected_rule
            "Protected by Spring Security #{auth_type} via #{match[1]}(\"#{url_pattern}\")"
          else
            "Public by Spring Security permitAll via #{match[1]}(\"#{url_pattern}\")"
          end
        rules << {pattern: url_pattern, method: matcher_method, description: description, protected_rule: protected_rule}
      end
    end

    # A scoped chain's `anyRequest()` covers its scope; an unscoped chain's
    # covers everything. A chain scoped by a matcher noir cannot read drops
    # it — the old behaviour, since what it covers is unknown.
    any_request_covered = scope.nil? || !scope.empty?
    block.each_line do |line|
      line.scan(KOTLIN_AUTHORIZE_RULE) do |match|
        auth_type = match[4]
        protected_rule = auth_type != "permitAll"
        if url_pattern = match[2]?
          verb = protected_rule ? "Protected by Spring Security #{auth_type}" : "Public by Spring Security permitAll"
          rules << {pattern: url_pattern, method: match[1]?, description: "#{verb} via authorize(\"#{url_pattern}\")", protected_rule: protected_rule}
        elsif any_request_covered && protected_rule
          rules << {pattern: "/**", method: nil, description: "Protected by Spring Security #{auth_type} via authorize(anyRequest)", protected_rule: true}
        end
      end
    end
    if any_request_covered && (match = block.match(ANY_REQUEST_AUTH))
      rules << {pattern: "/**", method: nil, description: "Protected by Spring Security #{match[1]} via anyRequest()", protected_rule: true}
    end

    if scope && !scope.empty?
      @scoped_chains << {scope: scope, order: chain_order(block), rules: rules}
    else
      @security_rules.concat(rules)
    end
  end

  # nil for a chain that serves every request; the scope's ant patterns
  # otherwise, empty when the chain is scoped by a matcher noir cannot read.
  private def chain_scope(block : String, strings : Hash(String, String), arrays : Hash(String, Array(String))) : Array(String)?
    scope : Array(String)? = nil
    block.scan(SCOPE_MATCHER_CALL) do |match|
      scope ||= [] of String
      open = match.byte_end(0) - 1
      next unless close = Noir::JSLiteralScanner.find_matching_paren_at_byte(block, open)
      args = block.byte_slice(open + 1, close - open - 1)
      if match[1]? == "securityMatchers"
        # `securityMatchers(m -> m.requestMatchers("/a/**", "/b/**"))`.
        args.scan(MATCHERS_CALL) do |inner|
          inner_open = inner.byte_end(0) - 1
          next unless inner_close = Noir::JSLiteralScanner.find_matching_paren_at_byte(args, inner_open)
          scope.concat(matcher_patterns(args.byte_slice(inner_open + 1, inner_close - inner_open - 1), strings, arrays))
        end
      else
        scope.concat(matcher_patterns(args, strings, arrays))
      end
    end
    scope.try &.uniq
  end

  # The `@Order` on the chain's bean method; unordered beans sort last.
  private def chain_order(block : String) : Int32
    boundary = (block =~ CHAIN_BOUNDARY) || 0
    header = block[0, block.index('\n', boundary) || block.size]
    return Int32::MAX unless match = header.match(ORDER_ANNOTATION)
    case value = match[1]
    when "Ordered.HIGHEST_PRECEDENCE" then Int32::MIN
    when "Ordered.LOWEST_PRECEDENCE"  then Int32::MAX
    else                                   value.to_i? || Int32::MAX
    end
  end

  # Ant patterns a matcher argument list names: string literals, String /
  # `String[]` constants, inline `new String[]{...}` arrays, and matcher
  # factories over those (`antMatcher(X)`, `new AntPathRequestMatcher(X)`).
  # Anything else (`EndpointRequest.toAnyEndpoint()`, a computed list) names
  # nothing noir can read and is skipped.
  private def matcher_patterns(args : String, strings : Hash(String, String), arrays : Hash(String, Array(String)), depth : Int32 = 0) : Array(String)
    patterns = [] of String
    return patterns if depth > 4

    Noir::TopLevelSplit.split(args, ',', Noir::TopLevelSplit::Rules.new).each do |part|
      if literal = part.match(JAVA_STRING_LITERAL)
        patterns << literal[1]
      elsif part.matches?(CONSTANT_REFERENCE)
        next if part.starts_with?("HttpMethod.")
        if values = arrays[part]?
          patterns.concat(values)
        elsif value = strings[part]?
          patterns << value
        end
      elsif inner = part.match(INLINE_STRING_ARRAY) || part.match(MATCHER_FACTORY_CALL)
        patterns.concat(matcher_patterns(inner[1], strings, arrays, depth + 1))
      end
    end
    patterns
  end

  # One block per SecurityFilterChain / `configure(HttpSecurity)`. The
  # annotations right above a boundary (`@Bean @Order(1)`) belong to the
  # chain below it, so they move into its block.
  private def split_into_chain_blocks(content : String) : Array(String)
    blocks = [] of String
    current = [] of String
    content.each_line do |raw|
      if raw.matches?(CHAIN_BOUNDARY) && !current.empty?
        header = [] of String
        while (last = current.last?) && (last.strip.empty? || last.lstrip.starts_with?('@'))
          header.unshift(current.pop)
        end
        blocks << current.join("\n") unless current.empty?
        current = header
      end
      current << raw
    end
    blocks << current.join("\n") unless current.empty?
    blocks
  end

  private def request_matcher_method(args : String) : String?
    if match = args.match(/\bHttpMethod\.(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\b/)
      return match[1]
    end

    nil
  end

  # A request inside a scoped chain's matcher is decided by that chain (the
  # lowest `@Order` when several match); every other request by the
  # catch-all chains. Within the deciding rules the most specific matching
  # pattern wins.
  private def check_security_config_rules(endpoint : Endpoint) : String?
    url = endpoint.url
    scoped = @scoped_chains.select { |chain| chain[:scope].any? { |pattern| matches_ant_pattern?(url, pattern) } }
    rules =
      if chain = scoped.min_by? { |candidate| {candidate[:order], -candidate[:scope].max_of { |pattern| matches_ant_pattern?(url, pattern) ? pattern_specificity(pattern) : 0 }} }
        chain[:rules]
      else
        @security_rules
      end
    matches = rules.select do |rule|
      rule_method = rule[:method]
      (!rule_method || rule_method == endpoint.method.upcase) && matches_ant_pattern?(url, rule[:pattern])
    end
    return if matches.empty?

    best = matches.max_by { |rule| pattern_specificity(rule[:pattern]) }
    return unless best[:protected_rule]

    best[:description]
  end

  private def matches_ant_pattern?(url : String, pattern : String) : Bool
    # Handle comma-separated patterns
    patterns = pattern.split(",").map(&.strip)
    normalized_url = normalize_security_path(url)

    patterns.any? do |p|
      p = normalize_security_path(p)
      next false if p.empty?

      normalized_url.matches?(ant_pattern_regex(p))
    end
  rescue ex
    @logger.debug "SpringAuthTagger: Failed to match ant pattern '#{pattern}': #{ex.message}"
    false
  end

  private def normalize_security_path(path : String) : String
    value = path.strip
    return value if value.empty?
    value.starts_with?("/") ? value : "/#{value}"
  end

  # Every endpoint is matched against every recorded security rule, so this is
  # called O(endpoints x rules) times over a small set of distinct patterns.
  # Memoize (as `spring_security` already does) so the same PCRE2 pattern isn't
  # recompiled thousands of times.
  @ant_pattern_regexes = Hash(String, Regex).new

  private def ant_pattern_regex(pattern : String) : Regex
    @ant_pattern_regexes[pattern] ||= begin
      # A trailing `/**` also matches the bare prefix (`/assets/**` serves
      # `/assets`), as Spring's ant and path-pattern matchers do.
      escaped = Regex.escape(pattern)
        .sub(/\/\\\*\\\*\z/, "(?:/.*)?")
        .gsub("\\*\\*", ".*")
        .gsub("\\*", "[^/]*")

      /^#{escaped}\/?$/
    end
  end

  private def pattern_specificity(pattern : String) : Int32
    pattern.split(",").max_of? do |part|
      normalize_security_path(part)
        .gsub("*", "")
        .size
    end || 0
  end

  private def check_annotations(ctx : SourceContext) : String?
    line = ctx.line
    return unless line

    # Walk backwards from endpoint line to find annotations
    # `line` is 1-indexed (from PathInfo), array is 0-indexed
    lines = ctx.lines
    endpoint_idx = line - 1

    idx = [endpoint_idx - 1, lines.size - 1].min
    while idx >= 0 && idx >= endpoint_idx - 15
      current_line = lines[idx].strip
      # Skip empty lines but stop at method/class boundaries
      if current_line.empty?
        idx -= 1
        next
      end
      break if current_line.starts_with?("public ") || current_line.starts_with?("private ") || current_line.starts_with?("protected ")
      break if current_line.starts_with?("class ") || current_line.starts_with?("}")
      break if current_line.ends_with?("}")
      # The previous handler's declaration: a Kotlin `fun admin() = "admin"`
      # or a bodiless interface method `String admin();`.
      break if current_line.ends_with?(";") || current_line.matches?(KOTLIN_FUN_DECLARATION)

      ANNOTATION_PATTERNS.each do |pattern|
        if current_line.matches?(pattern)
          annotation_name = current_line.split("(").first.strip
          return "Protected by Spring #{annotation_name}"
        end
      end

      idx -= 1
    end

    annotation_lines_below(lines, endpoint_idx, "@").each do |below|
      ANNOTATION_PATTERNS.each do |pattern|
        if below.matches?(pattern)
          annotation_name = below.split("(").first.strip
          return "Protected by Spring #{annotation_name}"
        end
      end
    end

    # A controller-level `@PreAuthorize`/`@Secured`/`@RolesAllowed` applies to
    # every handler the class declares. The walk above cannot reach it — it
    # stops at the `public`/`class` boundary by design, so a handler under an
    # `@PreAuthorize("hasRole('ADMIN')")` controller was reported as
    # unauthenticated. Check the class declaration separately.
    CLASS_ANNOTATION_NAMES.each do |annotation_name|
      if class_line = class_level_annotation(ctx.path, lines, annotation_name)
        return "Protected by Spring #{class_line.split("(").first.strip} on the controller class"
      end
    end

    nil
  end

  private def check_endpoint(endpoint : Endpoint)
    # Phase 2: Check annotations near code_paths
    contexts = read_source_context(endpoint)
    contexts.each do |ctx|
      description = check_annotations(ctx)
      if description
        endpoint.add_tag(Tag.new("auth", description, "spring_auth"))
        return
      end
    end

    # Phase 3: Match endpoint URL against security config rules
    description = check_security_config_rules(endpoint)
    if description
      endpoint.add_tag(Tag.new("auth", description, "spring_auth"))
    end
  end
end
