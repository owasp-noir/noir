require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../miniparsers/java_route_extractor_ts"
require "../../../utils/js_literal_scanner"
require "../../../utils/top_level_split"
require "../../../analyzer/engines/java_engine"

@[Noir::TaggerFor(key: "spring_auth", name: "Spring Auth Tagger", desc: "Identifies Spring Security patterns (annotations, security config)", order: 20)]
class SpringAuthTagger < FrameworkTagger
  record MetaAnnotation,
    name : String,
    spring_annotation : String

  record InterceptorDef,
    name : String,
    file_path : String,
    line : Int32,
    is_auth_guard : Bool,
    module_dir : String?

  record RegisteredInterceptor,
    interceptor_name : String,
    file_path : String,
    line : Int32,
    add_patterns : Array(String),
    exclude_patterns : Array(String),
    module_dir : String?

  alias PathTest = NamedTuple(path: String, exact: Bool)

  # A servlet filter class (`OncePerRequestFilter`, `GenericFilterBean`,
  # `Filter`). `refusal` ("401", "403", an exception name) is nil when its
  # `doFilter` does not turn a caller without a credential away. `required`
  # / `excluded` are the paths its `shouldNotFilter` and early
  # `chain.doFilter(...); return` pass-throughs leave it on: every set in
  # `required` must hold a test the URL passes, and no `excluded` one may.
  record ServletFilterDef,
    name : String,
    file_path : String,
    line : Int32,
    module_dir : String?,
    refusal : String?,
    component : Bool,
    web_filter_patterns : Array(String)?,
    required : Array(Array(PathTest)),
    excluded : Array(PathTest)

  # A `FilterRegistrationBean`: `names` are the filter types it may hold,
  # `patterns` its servlet URL patterns (nil: one noir cannot read).
  record ServletFilterRegistration,
    names : Array(String),
    file_path : String,
    line : Int32,
    patterns : Array(String)?,
    enabled : Bool,
    module_dir : String?

  ANNOTATION_PATTERNS = [
    /\@PreAuthorize\s*\(/,
    /\@PostAuthorize\s*\(/,
    /\@Secured\s*\(/,
    /\@RolesAllowed\s*\(/,
  ]

  # The same authorization annotations, as the bare names they are matched by
  # when they decorate the controller *class* instead of a single handler.
  CLASS_ANNOTATION_NAMES = ["@PreAuthorize", "@PostAuthorize", "@Secured", "@RolesAllowed"]

  # What a `preHandle` that turns the caller away does: a 401/403 status or
  # an auth exception. `return false` alone is not read: a rate limiter or
  # maintenance switch returns false too.
  INTERCEPTOR_REJECTION_RE = /(?:setStatus\s*\(\s*(?:40[13]|(?:HttpServletResponse\.)?SC_(?:UNAUTHORIZED|FORBIDDEN)|HttpStatus\.(?:UNAUTHORIZED|FORBIDDEN))\b|sendError\s*\(\s*(?:40[13]|(?:HttpServletResponse\.)?SC_(?:UNAUTHORIZED|FORBIDDEN)|HttpStatus\.(?:UNAUTHORIZED|FORBIDDEN))\b|\bstatus\s*=\s*(?:40[13]|(?:HttpServletResponse\.)?SC_(?:UNAUTHORIZED|FORBIDDEN)|HttpStatus\.(?:UNAUTHORIZED|FORBIDDEN))\b|throw\s+new\s+(?:\w*(?:Auth(?!or)|AccessDenied|Unauthorized|Forbidden|Security)\w*|ResponseStatusException\s*\(\s*HttpStatus\.(?:UNAUTHORIZED|FORBIDDEN))\b)/i

  # Security config URL rules. `access { ... }` is a protected rule too;
  # `permitAll()` is intentionally tracked so a more-specific public matcher
  # can suppress a broader protected one. The matcher's argument list is
  # found by paren matching (it nests `antMatcher(X)` calls and spans lines),
  # so only the call opener is a regex.
  MATCHERS_CALL    = /\.\s*(antMatchers|requestMatchers|mvcMatchers)\s*\(/
  RULE_AFTER_CALL  = /\A\s*\.\s*(permitAll|anonymous|denyAll|authenticated|fullyAuthenticated|hasRole|hasAnyRole|hasAuthority|hasAnyAuthority|access)\s*(?:\(|\{)/
  ANY_REQUEST_AUTH = /\.\s*anyRequest\s*\(\s*\)\s*\.\s*(permitAll|anonymous|denyAll|authenticated|fullyAuthenticated|hasRole|hasAnyRole|hasAuthority|hasAnyAuthority|access)\s*(?:\(|\{)/

  # The Kotlin DSL Spring Security documents for Kotlin apps:
  # `authorizeHttpRequests { authorize("/public/**", permitAll);
  # authorize(anyRequest, authenticated) }`.
  KOTLIN_AUTHORIZE_RULE = /\bauthorize\s*\(\s*(?:HttpMethod\.(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s*,\s*)?(?:"([^"]+)"|(anyRequest))\s*,\s*(permitAll|anonymous|denyAll|authenticated|fullyAuthenticated|hasRole|hasAnyRole|hasAuthority|hasAnyAuthority|access)\b/

  FORM_LOGIN_DSL     = /(?:\.\s*formLogin\s*\(|\bformLogin\s*\(|\bformLogin\s*\{)/
  FORM_LOGIN_SETTER  = /\b(loginPage|loginProcessingUrl|failureUrl)\s*(?:\(\s*|=\s*)/
  PERMIT_ALL_PATTERN = /\bpermitAll\s*\(\s*(?:true\s*)?\)/

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
  BOOT_APP_MARKERS     = {"@SpringBootApplication", "@SpringBootConfiguration", "SpringApplication.run", "runApplication<"}
  CHAIN_DECLARATION    = /\b(?:SecurityFilterChain|SecurityWebFilterChain|WebSecurityConfigurerAdapter)\b|configure\s*\(\s*(?:final\s+)?(?:Server)?HttpSecurity/

  KOTLIN_FUN_DECLARATION = /(?:^|\s)fun\s/

  # A method-security expression that admits an anonymous caller. Anything
  # else, including a mixed `permitAll() or hasRole(...)`, stays a guard.
  PUBLIC_SPEL     = /\A(?:permitAll\s*\(\s*\)|anonymous(?:\s*\(\s*\))?|isAnonymous\s*\(\s*\)|hasRole\s*\(\s*['"](?:ROLE_)?ANONYMOUS['"]\s*\)|hasAuthority\s*\(\s*['"](?:ROLE_)?ANONYMOUS['"]\s*\))\z/
  ANONYMOUS_ROLES = Set{"IS_AUTHENTICATED_ANONYMOUSLY", "ROLE_ANONYMOUS", "ANONYMOUS"}

  alias SecurityAnnotation = NamedTuple(public_access: Bool, description: String)

  # `module` is the build unit (Maven module) whose sources declare the
  # rule, nil when unknown. `config_key` marks a rule whose patterns are a
  # `@ConfigurationProperties` list (`for (String url : props.getUrls())
  # registry.requestMatchers(url).permitAll()`): they are read per endpoint
  # from the configuration of the module that serves it.
  alias SecurityRule = NamedTuple(pattern: String, method: String?, description: String, protected_rule: Bool, module: String?, config_key: String?, path: String?, line: Int32?)

  # A `securityMatcher`-scoped SecurityFilterChain: requests its `scope`
  # matches are served by this chain alone (Spring hands a request to the
  # first chain whose matcher matches, and the catch-all chain must come
  # last), so its rules decide them and no other chain's do.
  alias ScopedChain = NamedTuple(scope: Array(String), order: Int32, rules: Array(SecurityRule), module: String?)

  def initialize(options : Hash(String, YAML::Any))
    super
    # Rules of the chains that serve every request (and of chains scoped by
    # a matcher noir cannot read, which keep the old global treatment).
    @security_rules = [] of SecurityRule
    @scoped_chains = [] of ScopedChain
    # Build units that declare a security chain (nil: a file outside any),
    # and the ones holding a Boot entry point (`@SpringBootApplication`, `SpringApplication.run`).
    @chain_modules = Set(String?).new
    @boot_apps = Set(String).new
    @security_meta_annotations = Hash(String, MetaAnnotation).new
    @interceptor_defs = Hash(String, InterceptorDef).new
    @registered_interceptors = [] of RegisteredInterceptor
    @servlet_filters = Hash(String, ServletFilterDef).new
    @filter_registrations = [] of ServletFilterRegistration
    @bean_types = Set(String).new
    @servlet_component_scan = false
  end

  def self.target_techs : Array(String)
    ["java_spring", "kotlin_spring", "java_jaxrs"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    # Phase 1: Pre-scan security config files
    pre_scan_security_configs
    super
  end

  private def pre_scan_security_configs
    @security_rules.clear
    @scoped_chains.clear
    @chain_modules.clear
    @boot_apps.clear
    @security_meta_annotations.clear
    @interceptor_defs.clear
    @registered_interceptors.clear
    @servlet_filters.clear
    @filter_registrations.clear
    @bean_types.clear
    @servlet_component_scan = false

    # Find Java and Kotlin security config files
    extensions = [".java", ".kt"]
    extensions.each do |ext|
      files = collect_files_by_extension(ext)
      files.each do |file|
        content = read_file(file)
        next if content.nil?
        if !file.includes?("/src/test/") && BOOT_APP_MARKERS.any? { |marker| content.includes?(marker) } && (app = build_module(file))
          @boot_apps << app
        end

        module_dir = build_module(file)

        if content.includes?("@interface") || content.includes?("annotation class")
          scan_meta_annotations(content, file, module_dir)
        end

        if content.includes?("HandlerInterceptor") || content.includes?("HandlerInterceptorAdapter")
          scan_interceptor_def(content, file, module_dir)
        end

        if content.includes?("addInterceptors")
          scan_interceptor_registration(content, file, module_dir)
        end

        scan_servlet_filter_defs(content, file, module_dir) if content.includes?("doFilter")
        scan_filter_registrations(content, file, module_dir) if content.includes?("FilterRegistrationBean")
        scan_bean_types(content) if content.includes?("@Bean")
        @servlet_component_scan = true if content.includes?("@ServletComponentScan")

        next unless content.includes?("SecurityFilterChain") || content.includes?("HttpSecurity") || content.includes?("WebSecurityConfigurerAdapter")

        scan_security_config(content, file.ends_with?(".java"), module_dir, file)
      end
    end
  end

  private def scan_meta_annotations(content : String, file : String, module_dir : String?)
    clean_content = Noir::CComments.strip(content)
    lines = clean_content.lines

    lines.each_with_index do |line, idx|
      name = if match = line.match(/(?:public\s+|protected\s+|private\s+)?@interface\s+([A-Za-z0-9_$]+)/)
               match[1]
             elsif match = line.match(/\bannotation\s+class\s+([A-Za-z0-9_$]+)/)
               match[1]
             end
      next unless name

      annotations_text = [] of String
      j = idx - 1
      while j >= 0 && j >= idx - 20
        prev = lines[j].strip
        break if prev.starts_with?("package ") || prev.starts_with?("import ")
        break if prev.includes?("class ") || prev.includes?("@interface ")
        annotations_text.unshift(prev)
        j -= 1
      end
      annotations_text << line

      full_block = annotations_text.join("\n")
      if match = full_block.match(/@(PreAuthorize|PostAuthorize|Secured|RolesAllowed)\s*\(/)
        @security_meta_annotations[name] = MetaAnnotation.new(name, "@#{match[1]}")
      elsif @security_meta_annotations.present?
        @security_meta_annotations.each_value do |meta|
          if full_block.matches?(/(?:\A|[^@\w])@#{Regex.escape(meta.name)}\b/)
            @security_meta_annotations[name] = MetaAnnotation.new(name, meta.spring_annotation)
            break
          end
        end
      end
    end
  end

  private def scan_interceptor_def(content : String, file : String, module_dir : String?)
    clean_content = Noir::CComments.strip(content)
    lines = clean_content.lines

    lines.each_with_index do |line, idx|
      class_name = nil

      if match = line.match(/(?:public\s+|protected\s+|private\s+)?(?:final\s+|abstract\s+)?class\s+([A-Za-z0-9_$]+)[^{]*(?:implements\s+[^{]*\bHandlerInterceptor\b|extends\s+[^{]*\bHandlerInterceptorAdapter\b)/)
        class_name = match[1]
      elsif match = line.match(/(?:class|open\s+class)\s+([A-Za-z0-9_$]+)[^{:]*:\s*[^{]*(?:\bHandlerInterceptor\b|\bHandlerInterceptorAdapter\b)/)
        class_name = match[1]
      elsif line.includes?("HandlerInterceptor") || line.includes?("HandlerInterceptorAdapter")
        combined = lines[[0, idx - 2].max..idx].map(&.strip).join(" ")
        if match = combined.match(/class\s+([A-Za-z0-9_$]+)[^{:]*(?:implements|extends|:)[^{]*(?:\bHandlerInterceptor\b|\bHandlerInterceptorAdapter\b)/)
          class_name = match[1]
        end
      end

      next unless class_name

      # The class's own body: a file can declare several interceptors.
      line_start = clean_content.lines(chomp: false)[0, idx].sum(&.bytesize)
      next unless open = clean_content.byte_index('{', line_start)
      close = Noir::JSLiteralScanner.find_matching_brace_at_byte(clean_content, open) || clean_content.bytesize - 1
      is_auth = check_pre_handle_auth(clean_content.byte_slice(open, close - open + 1))
      @interceptor_defs[class_name] = InterceptorDef.new(
        name: class_name,
        file_path: file,
        line: idx + 1,
        is_auth_guard: is_auth,
        module_dir: module_dir
      )
    end
  end

  private def check_pre_handle_auth(content : String) : Bool
    pre_handle_match = content.match(/(?:\bboolean\s+preHandle\b|(?:override\s+)?fun\s+preHandle\b)[^{]*\{/m)
    return false unless pre_handle_match

    open_brace_idx = pre_handle_match.byte_end(0) - 1
    close_brace_idx = Noir::JSLiteralScanner.find_matching_brace_at_byte(content, open_brace_idx)
    body = close_brace_idx ? content.byte_slice(open_brace_idx + 1, close_brace_idx - open_brace_idx - 1) : content.byte_slice(open_brace_idx + 1, [content.bytesize - open_brace_idx - 1, 1500].min)

    body.matches?(INTERCEPTOR_REJECTION_RE)
  end

  private def scan_interceptor_registration(content : String, file : String, module_dir : String?)
    clean_content = Noir::CComments.strip(content)
    add_int_match = clean_content.match(/\baddInterceptors\s*\(\s*(?:(?:final\s+)?InterceptorRegistry\s+(\w+)|(\w+)\s*:\s*InterceptorRegistry)\s*\)[^{]*\{/m)
    return unless add_int_match

    reg_param = add_int_match[1]? || add_int_match[2]? || "registry"
    open_brace_idx = add_int_match.byte_end(0) - 1
    close_brace_idx = Noir::JSLiteralScanner.find_matching_brace_at_byte(clean_content, open_brace_idx)
    return unless close_brace_idx

    body = clean_content.byte_slice(open_brace_idx + 1, close_brace_idx - open_brace_idx - 1)
    reg_re = /(?:(?:InterceptorRegistration|val|var)\s+(\w+)\s*=\s*)?#{Regex.escape(reg_param)}\s*\.\s*addInterceptor\s*\(/m

    body.scan(reg_re) do |match|
      var_name = match[1]?
      call_open_paren = match.byte_end(0) - 1
      call_close_paren = Noir::JSLiteralScanner.find_matching_paren_at_byte(body, call_open_paren)
      next unless call_close_paren

      arg = body.byte_slice(call_open_paren + 1, call_close_paren - call_open_paren - 1).strip

      remaining = body.byte_slice(call_close_paren + 1, body.bytesize - call_close_paren - 1)
      # The statement ends at `;`, or in Kotlin at the next registration.
      stop = [remaining.index(';'), remaining.index(/\b#{Regex.escape(reg_param)}\s*\./)].compact.min?
      chain_slice = stop ? remaining[0...stop] : remaining[0, 500]

      chain_text = chain_slice
      if var_name
        body.scan(/\b#{Regex.escape(var_name)}\s*\.\s*(?:addPathPatterns|excludePathPatterns)\s*\(/m) do |vmatch|
          v_open = vmatch.byte_end(0) - 1
          if v_close = Noir::JSLiteralScanner.find_matching_paren_at_byte(body, v_open)
            chain_text += "\n" + body.byte_slice(vmatch.byte_begin(0), v_close - vmatch.byte_begin(0) + 1)
          end
        end
      end

      add_patterns = [] of String
      chain_text.scan(/\.addPathPatterns\s*\(/) do |pmatch|
        p_open = pmatch.byte_end(0) - 1
        if p_close = Noir::JSLiteralScanner.find_matching_paren_at_byte(chain_text, p_open)
          p_args = chain_text.byte_slice(p_open + 1, p_close - p_open - 1)
          p_args.scan(/"((?:[^"\\]|\\.)*)"/) { |sm| add_patterns << sm[1] }
        end
      end

      add_patterns = ["/**"] if add_patterns.empty?

      exclude_patterns = [] of String
      chain_text.scan(/\.excludePathPatterns\s*\(/) do |pmatch|
        p_open = pmatch.byte_end(0) - 1
        if p_close = Noir::JSLiteralScanner.find_matching_paren_at_byte(chain_text, p_open)
          p_args = chain_text.byte_slice(p_open + 1, p_close - p_open - 1)
          p_args.scan(/"((?:[^"\\]|\\.)*)"/) { |sm| exclude_patterns << sm[1] }
        end
      end

      interceptor_type = resolve_interceptor_type(arg, clean_content)
      next unless interceptor_type

      match_byte_in_content = open_brace_idx + 1 + match.byte_begin(0)
      line_num = clean_content.byte_slice(0, match_byte_in_content).count('\n') + 1

      @registered_interceptors << RegisteredInterceptor.new(
        interceptor_name: interceptor_type,
        file_path: file,
        line: line_num,
        add_patterns: add_patterns,
        exclude_patterns: exclude_patterns,
        module_dir: module_dir
      )
    end
  end

  private def resolve_interceptor_type(arg : String, content : String) : String?
    if match = arg.match(/\bnew\s+([A-Za-z0-9_$]+)\s*\(/)
      return match[1]
    elsif match = arg.match(/\A\s*([A-Z][A-Za-z0-9_$]*)\s*\(/)
      return match[1]
    end

    ident = arg.sub(/\s*\(.*\)\z/, "").strip
    return if ident.empty?

    if match = content.match(/(?:private|protected|public)?\s*(?:final\s+)?([A-Za-z0-9_$]+)\s+#{Regex.escape(ident)}\s*;/m)
      type_name = match[1]
      return type_name if type_name != "var" && type_name != "val"
    end

    if match = content.match(/\b([A-Za-z0-9_$]+)\s+#{Regex.escape(ident)}\b[,\)]/)
      type_name = match[1]
      return type_name if type_name != "final" && type_name != "var" && type_name != "val"
    elsif match = content.match(/\b#{Regex.escape(ident)}\s*:\s*([A-Za-z0-9_$]+)/)
      return match[1]
    end

    if match = content.match(/\b([A-Za-z0-9_$]+)\s+#{Regex.escape(ident)}\s*\(\s*\)/)
      return match[1]
    elsif match = content.match(/fun\s+#{Regex.escape(ident)}\s*\(\s*\)\s*:\s*([A-Za-z0-9_$]+)/)
      return match[1]
    end

    return ident if ident[0].ascii_uppercase?

    capitalized = ident[0].upcase + ident[1..]
    capitalized
  end

  # A servlet filter class header: Java `extends OncePerRequestFilter` /
  # `implements Filter`, Kotlin `: OncePerRequestFilter()` / `: Filter`.
  SERVLET_FILTER_CLASS  = /\bclass\s+([A-Za-z_$][\w$]*)[^{;]*?(?:\bextends\s+(?:[\w.]+\.)?(?:OncePerRequestFilter|GenericFilterBean|HttpFilter)\b|\bimplements\s+[^{;]*?\b(?:[\w.]+\.)?Filter\b(?!\s*[<.])|:\s*(?:[^{;]*?,\s*)?(?:[\w.]+\.)?(?:(?:OncePerRequestFilter|GenericFilterBean|HttpFilter)\s*\(|Filter\b(?!\s*[<.(])))/
  DO_FILTER_DECLARATION = /(?:\bvoid|\bfun)\s+(?:doFilterInternal|doFilter)\s*\(/
  SHOULD_NOT_FILTER     = /(?:\bboolean|\bfun)\s+shouldNotFilter\s*\(/
  # A 401/403 status handed to a response helper (`writeError(res, SC_UNAUTHORIZED)`)
  # or a call named for the refusal (`sendUnauthorized(res)`, Kotlin `throw ForbiddenException()`).
  REFUSAL_STATUS_CONSTANT = /\b(?:HttpServletResponse\.)?SC_(?:UNAUTHORIZED|FORBIDDEN)\b|\bHttpStatus\.(?:UNAUTHORIZED|FORBIDDEN)\b|\b\w*(?:Unauthori[sz]ed|Forbidden)\w*\s*\(/i
  # Filters that refuse for another reason than a missing credential.
  # ponytail: a name list; a filter named for its credential check is not read further.
  NON_AUTH_FILTER_NAME = /Csrf|Xsrf|Origin|Refer|RateLimit|Throttl|Cors|Xss/i
  # Reading what the caller presents as a credential. Without one, a filter
  # that refuses with 403 checks something else (a Referer allowlist, an IP).
  FILTER_CREDENTIAL_READ = /\bget(?:Header|Parameter)\s*\(\s*(?:HttpHeaders\.AUTHORIZATION\b|"[^"]*(?:auth|token|key|jwt|bearer|session|credential)[^"]*"|[\w$.]*(?:auth|token|key|jwt|session)[\w$]*(?:\s*\(\s*\))?\s*\))|\bgetSession\s*\(|\brequest\.session\b|\b(?:getUserPrincipal|userPrincipal|getRemoteUser|remoteUser|SecurityContextHolder)\b|\bgetCookies\s*\(|\.cookies\b|\b\w*(?:token|auth|jwt|session|credential|principal)\w*\s*\(\s*(?:request|req|httpRequest|httpServletRequest|servletRequest)\b[^()]*\)/i
  # A credential read with its receiver (`request.getHeader("X-Api-Key")`).
  CREDENTIAL_EXPRESSION = /(?:[\w$]+\s*\.\s*)*(?:#{FILTER_CREDENTIAL_READ.source})/i
  # A test that the credential is missing (or a prefix like `Bearer ` is):
  # a pass-through on it lets anonymous callers in.
  ABSENCE_TEST = /==\s*null\b|\bnull\s*==|\b(?:isEmpty|isBlank|isNullOrEmpty|isNullOrBlank|hasText|hasLength|isNotEmpty|isNotBlank|startsWith)\b/
  # The condition a refusal sits under, when it turns away a caller without
  # a credential: negated (`!valid(token)`, `key != expected`) or an absence test.
  REFUSAL_CONDITION = /!|#{ABSENCE_TEST.source}/
  # `path.startsWith("/admin")`, `request.servletPath == "/login"`.
  PATH_TEST = /(!\s*)?((?:[\w$]+(?:\s*\(\s*\))?\s*\.\s*)*[\w$]+(?:\s*\(\s*\))?)\s*(?:\.\s*(startsWith|equals)\s*\(\s*"(\/[^"]*)"\s*\)|(==|!=)\s*"(\/[^"]*)")/
  # `request.requestURI in OPEN`, `OPEN.contains(uri)` over a field of literals.
  MEMBERSHIP_TEST = /(!\s*)?(?:(?:[\w$]+(?:\s*\(\s*\))?\s*\.\s*)*[\w$]+(?:\s*\(\s*\))?\s+(!?in)\s+([A-Za-z_$][\w$]*)\b(?!\s*[.(])|([A-Za-z_$][\w$]*)\s*\.\s*contains\s*\(\s*(?:[\w$]+(?:\s*\(\s*\))?\s*\.\s*)*[\w$]+(?:\s*\(\s*\))?\s*\))/

  private def scan_servlet_filter_defs(content : String, file : String, module_dir : String?)
    clean = Noir::CComments.strip(content)
    clean.scan(SERVLET_FILTER_CLASS) do |match|
      name = match[1]
      next unless open = clean.byte_index('{', match.byte_end(0) - 1)
      close = Noir::JSLiteralScanner.find_matching_brace_at_byte(clean, open) || clean.bytesize - 1
      body = clean.byte_slice(open, close - open + 1)
      lead_start = [match.byte_begin(0) - 600, 0].max
      lead = clean.byte_slice(lead_start, match.byte_begin(0) - lead_start).scrub
      lead = lead[((lead.rindex(/[;}][ \t]*\r?\n/) || -1) + 1)..]

      filter = ServletFilterDef.new(
        name: name,
        file_path: file,
        line: clean.byte_slice(0, match.byte_begin(0)).count('\n') + 1,
        module_dir: module_dir,
        refusal: nil,
        component: lead.matches?(/@Component\b/),
        web_filter_patterns: web_filter_patterns(lead),
        required: [] of Array(PathTest),
        excluded: [] of PathTest
      )
      @servlet_filters[name] = judge_servlet_filter(filter, body) || filter
    end
  end

  # `filter` with the refusal and pass-through paths read from its class
  # `body`; nil when it is not an auth guard: it reads no credential, does
  # not refuse, or lets requests through on a condition noir cannot read as
  # a path test (a missing token, a whitelist).
  private def judge_servlet_filter(filter : ServletFilterDef, body : String) : ServletFilterDef?
    return if filter.name.matches?(NON_AUTH_FILTER_NAME) || body.matches?(/csrf|xsrf/i) || !body.matches?(FILTER_CREDENTIAL_READ)
    return unless decl = body.match(DO_FILTER_DECLARATION)
    return unless params = paren_inner(body, decl.byte_end(0) - 1)
    return unless open = body.byte_index('{', params[1])
    return unless close = Noir::JSLiteralScanner.find_matching_brace_at_byte(body, open)
    method = body.byte_slice(open + 1, close - open - 1)

    # The first refusal in doFilter: a 401/403 status or auth exception, a
    # status constant handed to a helper, or a call to a class method that refuses.
    helpers = refusing_helpers(body)
    candidates = [method.match(INTERCEPTOR_REJECTION_RE), method.match(REFUSAL_STATUS_CONSTANT)]
    helpers.each_key { |helper| candidates << method.match(/\b#{Regex.escape(helper)}\s*\(/) }
    return unless first = candidates.compact.min_by?(&.begin(0))
    # A refusal only when the caller presents something (`if (hasSessionCookie(req))`)
    # lets an anonymous caller through: it must sit under a negated or absence test.
    if (cond = enclosing_condition(method, first.begin(0))) && !cond.matches?(REFUSAL_CONDITION)
      return
    end
    refusal_text = helpers.find { |helper, _| first[0].starts_with?(helper) }.try(&.[1]) || first[0]
    refusal = if refusal_text.matches?(/401|UNAUTHORIZED/i)
                "401"
              elsif refusal_text.matches?(/403|FORBIDDEN/i)
                "403"
              else
                refusal_text.match(/new\s+([\w$]+)/).try(&.[1]) || "an exception"
              end

    required = [] of Array(PathTest)
    excluded = [] of PathTest
    # Early pass-throughs: `if (cond) { chain.doFilter(..); return; }`.
    names = request_names(params[0], method)
    method[0, first.begin(0)].scan(/(\breturn\s+)?(?:[\w$]+\s*\.\s*)+doFilter\s*\(/) do |call|
      next unless call[1]? || method[call.end(0)..].matches?(/\A[^;{}]*\)\s*;?\s*return\b/)
      # ponytail: the condition is the nearest `if (` before the call, not an AST read.
      return unless cond_at = method[0, call.begin(0)].rindex(/\bif\s*\(/)
      paren = method.index!('(', cond_at)
      return unless cond_close = Noir::JSLiteralScanner.find_matching_paren(method, paren)
      return unless read_skip_condition(method[(paren + 1)...cond_close], names, body, required, excluded)
    end

    if skip = body.match(SHOULD_NOT_FILTER)
      return unless read_should_not_filter(body, skip, required, excluded)
    end

    filter.copy_with(refusal: refusal, required: required, excluded: excluded)
  end

  # The condition of the innermost `if` whose block (or single statement)
  # holds char offset `pos` of `code`; nil at the top level.
  private def enclosing_condition(code : String, pos : Int32) : String?
    ifs = [] of Int32
    code[0, pos].scan(/\bif\s*\(/) { |found| ifs << found.end(0) - 1 }
    ifs.reverse_each do |paren|
      next unless close = Noir::JSLiteralScanner.find_matching_paren(code, paren)
      next if close >= pos
      after = code[(close + 1)..]
      body_at = close + 1 + after.size - after.lstrip.size
      stop = if code[body_at]? == '{'
               Noir::JSLiteralScanner.find_matching_brace(code, body_at)
             else
               code.index(/[;\n]/, body_at)
             end
      return code[(paren + 1)...close] if stop.nil? || stop > pos
    end
    nil
  end

  # Methods of a filter class whose body refuses the request, with the refusing text.
  private def refusing_helpers(body : String) : Hash(String, String)
    helpers = Hash(String, String).new
    body.scan(/(?:\bfun|\bvoid|\b[\w$<>\[\]]+)\s+([a-z_$][\w$]*)\s*\(/) do |decl|
      name = decl[1]
      next if name.starts_with?("doFilter") || name == "shouldNotFilter"
      next unless params = paren_inner(body, decl.byte_end(0) - 1)
      rest = params[1]
      next unless open = body.byte_index('{', rest)
      next unless body.byte_slice(rest, open - rest).matches?(/\A[^;=]*\z/)
      next unless close = Noir::JSLiteralScanner.find_matching_brace_at_byte(body, open)
      if found = body.byte_slice(open, close - open + 1).match(INTERCEPTOR_REJECTION_RE)
        helpers[name] = found[0]
      end
    end
    helpers
  end

  # The request parameter of a filter method (the first one) and the locals
  # derived from it (`String path = request.getRequestURI()`), then the
  # subset of those holding the caller's credential (`token = request.getHeader("Authorization")`).
  private def request_names(params : String, body : String) : {Set(String), Set(String)}
    first = Noir::TopLevelSplit.split(params, ',', Noir::TopLevelSplit::Rules.new).first? || ""
    name = first.includes?(':') ? first.split(':').first : first.split(/\s+/).last
    tainted = Set{name.strip}
    credential = Set(String).new
    2.times do
      body.scan(/\b([a-z_$][\w$]*)\s*(?::\s*[\w$.<>?]+\s*)?=(?!=)\s*([^;\n]+)/) do |assign|
        idents = assign[2].scan(/[A-Za-z_$][\w$]*/).map(&.[0])
        tainted << assign[1] if idents.any? { |ident| tainted.includes?(ident) }
        credential << assign[1] if assign[2].matches?(FILTER_CREDENTIAL_READ) || idents.any? { |ident| credential.includes?(ident) }
      end
    end
    {tainted, credential}
  end

  # `shouldNotFilter` returns true for the requests the filter skips: read
  # its expression body, or the `if (c) return true` / `return e` of its block.
  private def read_should_not_filter(body : String, decl : Regex::MatchData, required : Array(Array(PathTest)), excluded : Array(PathTest)) : Bool
    return false unless params = paren_inner(body, decl.byte_end(0) - 1)
    rest = body.byte_slice(params[1])
    if expr = rest.match(/\A\s*(?::\s*Boolean\s*)?=\s*(.+?)(?=\n\s*(?:override\b|fun\b|public\b|protected\b|private\b|@|\})|\z)/m)
      return read_skip_condition(expr[1], request_names(params[0], expr[1]), body, required, excluded)
    end
    return false unless (open = rest.index('{')) && (close = Noir::JSLiteralScanner.find_matching_brace(rest, open))
    block = rest[(open + 1)...close]
    names = request_names(params[0], block)
    conditions = [] of String
    block.scan(/\bif\s*\(/) do |found|
      return false unless cond_close = Noir::JSLiteralScanner.find_matching_paren(block, found.end(0) - 1)
      returned = block[(cond_close + 1)..].match(/\A\s*\{?\s*return\s+(true|false)\b/)
      return false if returned.nil? || returned[1] == "false"
      conditions << block[found.end(0)...cond_close]
    end
    block.scan(/(?:\A|[;{}\n])\s*return\s+([^;\n]+)/) do |ret|
      next if ret[1].strip == "false" || block[0, ret.begin(0) + 1].matches?(/\bif\s*\([^;{}]*\)\s*\{?\s*\z/)
      conditions << ret[1]
    end
    conditions.all? { |cond| read_skip_condition(cond, names, body, required, excluded) }
  end

  # Reads a condition under which the filter lets a request through
  # unchecked. Each `||` disjunct is one of: a config switch that does not
  # look at the request, or a CORS preflight (ignored: the guard is on when
  # enabled); a valid credential (`claims != null`, `matches(request.getHeader(K))`:
  # the guard's own success path); `!p.startsWith(X) [&& !p.startsWith(Y)]`
  # or `p !in OPEN` (the filter runs only there); a single `p.startsWith(X)`
  # or `p in OPEN` (it never runs there). Anything else, a missing
  # credential in particular, makes the filter no guard: false.
  private def read_skip_condition(cond : String, names : {Set(String), Set(String)}, body : String, required : Array(Array(PathTest)), excluded : Array(PathTest)) : Bool
    tainted, credential = names
    Noir::TopLevelSplit.split(cond, "||", Noir::TopLevelSplit::Rules.new).each do |disjunct|
      while disjunct.starts_with?('(') && Noir::JSLiteralScanner.find_matching_paren(disjunct, 0) == disjunct.size - 1
        disjunct = disjunct[1...-1].strip
      end
      return false if disjunct == "true"
      idents = disjunct.gsub(STRING_LITERAL, "\"\"").scan(/[A-Za-z_$][\w$]*/).map(&.[0])
      next if idents.none? { |ident| tainted.includes?(ident) } || disjunct.matches?(/"OPTIONS"|HttpMethod\.OPTIONS\b/)

      if tests = path_tests(disjunct, body)
        if tests.all?(&.[1])
          required << tests.flat_map(&.[0])
        elsif tests.size == 1
          excluded.concat(tests[0][0])
        else
          return false
        end
        next
      end

      rest = disjunct.gsub(CREDENTIAL_EXPRESSION, " ")
      rest_idents = rest.gsub(STRING_LITERAL, "\"\"").scan(/[A-Za-z_$][\w$]*/).map(&.[0])
      return false if rest.matches?(ABSENCE_TEST)
      return false unless rest != disjunct || rest_idents.any? { |ident| credential.includes?(ident) }
      return false unless rest_idents.all? { |ident| !tainted.includes?(ident) || credential.includes?(ident) }
    end
    true
  end

  # The path tests a disjunct is made of, each with whether it is negated
  # (the filter runs only on its paths); nil when it holds anything else.
  private def path_tests(disjunct : String, body : String) : Array({Array(PathTest), Bool})?
    tests = [] of {Array(PathTest), Bool}
    disjunct.scan(PATH_TEST) do |test|
      negated = !test[1]?.nil? ^ (test[5]? == "!=")
      tests << {[{path: test[4]? || test[6], exact: test[3]? != "startsWith"}], negated}
    end
    disjunct.scan(MEMBERSHIP_TEST) do |test|
      field = test[3]? || test[4]
      return unless value = body.match(/\b#{Regex.escape(field)}\s*(?::[^=\n]+)?=\s*([^;\n]+)/)
      return unless (paths = servlet_url_patterns(value[1].strip)) && paths.all?(&.starts_with?('/'))
      tests << {paths.map { |path| {path: path, exact: true} }, !test[1]?.nil? ^ (test[2]? == "!in")}
    end
    return if tests.empty? || !disjunct.gsub(PATH_TEST, "").gsub(MEMBERSHIP_TEST, "").matches?(/\A[\s&()]*\z/)
    tests
  end

  # The text inside the parenthesis opening at byte `open` of `text`, and
  # the byte offset just past its `)`.
  private def paren_inner(text : String, open : Int32) : {String, Int32}?
    return unless close = Noir::JSLiteralScanner.find_matching_paren_at_byte(text, open)
    {text.byte_slice(open + 1, close - open - 1), close + 1}
  end

  private def path_test_matches?(url : String, test : PathTest) : Bool
    test[:exact] ? url.rchop('/') == test[:path].rchop('/') : url.starts_with?(test[:path])
  end

  # `@WebFilter("/a/*")`, `@WebFilter(urlPatterns = {"/a/*", "/b/*"})`,
  # `@WebFilter(value = ["/a/*"])`; nil without one.
  private def web_filter_patterns(lead : String) : Array(String)?
    return unless found = lead.match(/@WebFilter\s*\(/)
    return unless args = paren_inner(lead, found.byte_end(0) - 1)
    Noir::TopLevelSplit.split(args[0], ',', Noir::TopLevelSplit::Rules.new).each do |part|
      if named = part.match(/\A(?:urlPatterns|value)\s*=\s*(.+)\z/m)
        return servlet_url_patterns(named[1])
      elsif !part.includes?('=')
        return servlet_url_patterns(part)
      end
    end
    nil
  end

  # Servlet URL patterns spelled as literals, or nil when one is not
  # (`Constants.PREFIX + "/*"`, a property).
  private def servlet_url_patterns(args : String) : Array(String)?
    patterns = [] of String
    Noir::TopLevelSplit.split(args, ',', Noir::TopLevelSplit::Rules.new).each do |part|
      if literal = part.match(JAVA_STRING_LITERAL)
        patterns << literal[1]
      elsif wrapped = part.match(/\A(?:(?:List|Set|Arrays|Collections)\s*\.\s*(?:of|asList|singletonList|singleton)|listOf|setOf|arrayOf|mutableListOf)\s*\((.*)\)\z/m) ||
                      part.match(/\A(?:new\s+String\s*\[\s*\]\s*)?\{(.*)\}\z/m) || part.match(/\A\[(.*)\]\z/m)
        return unless inner = servlet_url_patterns(wrapped[1])
        patterns.concat(inner)
      else
        return
      end
    end
    patterns
  end

  # `new FilterRegistrationBean<>(..)` / Kotlin `FilterRegistrationBean(..)`;
  # not the type in a declaration (`FilterRegistrationBean<X> reg(`).
  FILTER_REGISTRATION_NEW = /\bnew\s+FilterRegistrationBean\b(?:\s*<[^>]*>)?\s*\(|(?<![\w.$])FilterRegistrationBean\s*(?:<[^>()]*>)?\s*\(/

  private def scan_filter_registrations(content : String, file : String, module_dir : String?)
    clean = Noir::CComments.strip(content)
    starts = [] of Regex::MatchData
    clean.scan(FILTER_REGISTRATION_NEW) { |found| starts << found }
    starts.each_with_index do |found, index|
      # The registration's statements: up to the next registration or member declaration.
      stop = starts[index + 1]?.try(&.byte_begin(0)) || clean.bytesize
      chunk = clean.byte_slice(found.byte_begin(0), stop - found.byte_begin(0))
      if member = chunk.match(/\n\s*(?:public\b|protected\b|private\b|fun\b|override\b|@)/)
        chunk = chunk[0, member.begin(0)]
      end

      args = [] of String
      if ctor = paren_inner(clean, found.byte_end(0) - 1)
        first = Noir::TopLevelSplit.split(ctor[0], ',', Noir::TopLevelSplit::Rules.new).first?
        args << first if first && !first.empty?
      end
      chunk.scan(/\bsetFilter\s*\(/) do |setter|
        if arg = paren_inner(chunk, setter.byte_end(0) - 1)
          args << arg[0]
        end
      end
      chunk.scan(/(?<![\w.$])filter\s*=\s*([^;\n]+)/) { |assign| args << assign[1].strip }
      names = args.compact_map { |arg| resolve_interceptor_type(arg, clean) }
      if names.empty?
        lead_start = [found.byte_begin(0) - 300, 0].max
        lead = clean.byte_slice(lead_start, found.byte_begin(0) - lead_start).scrub + found[0]
        lead.scan(/FilterRegistrationBean\s*<\s*([A-Z][\w$]*)/) { |generic| names = [generic[1]] }
      end
      next if names.empty?

      patterns = [] of String
      readable = true
      chunk.scan(/\b(?:addUrlPatterns|setUrlPatterns)\s*\(|\burlPatterns\s*=\s*/) do |call|
        value = if call[0].ends_with?('(')
                  paren_inner(chunk, call.byte_end(0) - 1).try(&.[0])
                else
                  chunk.byte_slice(call.byte_end(0)).match(/\A[^;\n]+/).try(&.[0].strip)
                end
        if value && (read = servlet_url_patterns(value))
          patterns.concat(read)
        else
          readable = false
        end
      end
      # A registration without URL patterns maps the filter to every request.
      patterns << "/*" if readable && patterns.empty?

      @filter_registrations << ServletFilterRegistration.new(
        names: names.uniq,
        file_path: file,
        line: clean.byte_slice(0, found.byte_begin(0)).count('\n') + 1,
        patterns: readable ? patterns : nil,
        enabled: !chunk.matches?(/\bsetEnabled\s*\(\s*false\s*\)|\b(?:isEnabled|enabled)\s*=\s*false\b/),
        module_dir: module_dir
      )
    end
  end

  # Types returned by `@Bean` methods: Spring Boot maps a filter bean to
  # every request unless a `FilterRegistrationBean` registers it.
  private def scan_bean_types(content : String)
    clean = Noir::CComments.strip(content)
    clean.scan(/@Bean\b/) do |found|
      after = clean.byte_slice(found.byte_end(0), [clean.bytesize - found.byte_end(0), 400].min).scrub
      if java = after.match(/\A(?:\s*@[\w.]+(?:\([^)]*\))?)*\s*(?:(?:public|protected|private|static|final)\s+)*([A-Z][\w$]*)(?:\s*<[^>]*>)?\s+[a-z_$][\w$]*\s*\(/)
        @bean_types << java[1]
      elsif kotlin = after.match(/\A(?:\s*@[\w.]+(?:\([^)]*\))?)*\s*(?:\w+\s+)*fun\s+[\w$]+\s*\([^)]*\)\s*(?::\s*([A-Z][\w$]*)|=\s*([A-Z][\w$]*)\s*\()/)
        @bean_types << (kotlin[1]? || kotlin[2])
      end
    end
  end

  # "Protected by Servlet filter X on PATTERN (refuses with N)" when a
  # refusing filter on the classpath is mapped to the endpoint URL.
  private def servlet_filter_decision(endpoint : Endpoint, classpath : Set(String)?) : Tuple(String, String, Int32)?
    url = normalize_security_path(endpoint.url)
    applies = ->(owner : String?) { owner.nil? || classpath.nil? || classpath.includes?(owner) }

    @servlet_filters.each_value do |filter|
      next unless refusal = filter.refusal
      next unless filter.required.all? { |tests| tests.any? { |test| path_test_matches?(url, test) } }
      next if filter.excluded.any? { |test| path_test_matches?(url, test) }

      mappings = [] of {String, String, Int32}
      registrations = @filter_registrations.select(&.names.includes?(filter.name))
      registrations.each do |reg|
        next unless reg.enabled && applies.call(reg.module_dir)
        reg.patterns.try &.each { |pattern| mappings << {pattern, reg.file_path, reg.line} }
      end
      if applies.call(filter.module_dir)
        # Spring Boot maps a filter bean it finds no registration for to `/*`.
        # ponytail: a `@Component @WebFilter` class is read as its `@WebFilter`
        # patterns, though Boot registers that bean for `/*` as well.
        if registrations.empty? && filter.web_filter_patterns.nil? && (filter.component || @bean_types.includes?(filter.name))
          mappings << {"/*", filter.file_path, filter.line}
        end
        if (patterns = filter.web_filter_patterns) && (@servlet_component_scan || @boot_apps.empty?)
          patterns.each { |pattern| mappings << {pattern, filter.file_path, filter.line} }
        end
      end

      next unless mapping = mappings.find { |pattern, _, _| servlet_pattern_matches?(url, pattern) }
      scope = mapping[0]
      if scope == "/*" && (inside = filter.required.flatten.find { |test| path_test_matches?(url, test) })
        scope = inside[:exact] ? inside[:path] : "#{inside[:path]}*"
      end
      return {"Protected by Servlet filter #{filter.name} on #{scope} (refuses with #{refusal})", mapping[1], mapping[2]}
    end
    nil
  end

  # Servlet URL-pattern matching: `/x/*` prefix, `*.ext` extension, `/` and
  # `/*` everything, otherwise exact.
  private def servlet_pattern_matches?(url : String, pattern : String) : Bool
    if pattern == "/" || pattern == "/*"
      true
    elsif pattern.ends_with?("/*")
      prefix = pattern[0...-2]
      url == prefix || url.starts_with?("#{prefix}/")
    elsif pattern.starts_with?("*.")
      url.ends_with?(pattern[1..])
    else
      url.rchop('/') == normalize_security_path(pattern).rchop('/')
    end
  end

  private def scan_security_config(content : String, java : Bool, module_dir : String?, file_path : String)
    strings, arrays = java ? security_constants(content) : {Hash(String, String).new, Hash(String, Array(String)).new}
    code = Noir::CComments.strip(content)
    # A declared chain replaces Boot's default one even when it adds no
    # authorization rule (`anyRequest().permitAll()`, csrf/cors only).
    @chain_modules << module_dir if code.matches?(CHAIN_DECLARATION)
    split_into_chain_blocks(code).each do |block, block_start_line|
      scan_security_chain(block, strings, arrays, module_dir, java ? code : nil, file_path, block_start_line)
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

  private def scan_security_chain(block : String, strings : Hash(String, String), arrays : Hash(String, Array(String)), module_dir : String?, java_source : String?, file_path : String, block_start_line : Int32)
    scope = chain_scope(block, strings, arrays)
    rules = [] of SecurityRule
    loops = java_source ? loop_bindings(block) : [] of LoopBinding

    block.scan(MATCHERS_CALL) do |match|
      open = match.byte_end(0) - 1
      next unless close = Noir::JSLiteralScanner.find_matching_paren_at_byte(block, open)
      slice_len = Math.min(96, block.bytesize - (close + 1))
      next unless rule = block.byte_slice(close + 1, slice_len).match(RULE_AFTER_CALL)

      args = block.byte_slice(open + 1, close - open - 1)
      auth_type = rule[1]
      is_anonymous = auth_type == "anonymous" ||
                     (auth_type == "hasRole" && block.byte_slice(close + 1, slice_len).matches?(/\A\s*\.\s*hasRole\s*\(\s*["'](?:ROLE_)?ANONYMOUS["']\s*\)/)) ||
                     (auth_type == "hasAuthority" && block.byte_slice(close + 1, slice_len).matches?(/\A\s*\.\s*hasAuthority\s*\(\s*["'](?:ROLE_)?ANONYMOUS["']\s*\)/))
      protected_rule = auth_type != "permitAll" && !is_anonymous
      matcher_method = request_matcher_method(args)
      config_keys = [] of String
      in_scope = loops_enclosing(loops, open)
      rule_line = block_start_line + block[0, match.begin(1)].count('\n')
      matcher_patterns(args, strings, arrays, loops: in_scope, config_keys: config_keys, java_source: java_source).uniq.each do |url_pattern|
        description =
          if protected_rule
            "Protected by Spring Security #{auth_type} via #{match[1]}(\"#{url_pattern}\")"
          elsif is_anonymous
            "Public by Spring Security anonymous via #{match[1]}(\"#{url_pattern}\")"
          else
            "Public by Spring Security permitAll via #{match[1]}(\"#{url_pattern}\")"
          end
        rules << {pattern: url_pattern, method: matcher_method, description: description, protected_rule: protected_rule, module: module_dir, config_key: nil, path: file_path, line: rule_line}
      end
      config_keys.uniq.each do |key|
        rules << {pattern: "", method: matcher_method, description: auth_type, protected_rule: protected_rule, module: module_dir, config_key: key, path: file_path, line: rule_line}
      end
    end

    scan_form_login_rules(block, strings, file_path, block_start_line, module_dir).each do |rule|
      rules << rule
    end

    # A scoped chain's `anyRequest()` covers its scope; an unscoped chain's
    # covers everything. A chain scoped by a matcher noir cannot read drops
    # it — the old behaviour, since what it covers is unknown.
    any_request_covered = scope.nil? || !scope.empty?
    block.each_line.with_index(block_start_line) do |line, line_num|
      line.scan(KOTLIN_AUTHORIZE_RULE) do |match|
        auth_type = match[4]
        is_anonymous = auth_type == "anonymous"
        protected_rule = auth_type != "permitAll" && !is_anonymous
        if url_pattern = match[2]?
          verb =
            if protected_rule
              "Protected by Spring Security #{auth_type}"
            elsif is_anonymous
              "Public by Spring Security anonymous"
            else
              "Public by Spring Security permitAll"
            end
          rules << {pattern: url_pattern, method: match[1]?, description: "#{verb} via authorize(\"#{url_pattern}\")", protected_rule: protected_rule, module: module_dir, config_key: nil, path: file_path, line: line_num}
        elsif any_request_covered
          verb =
            if protected_rule
              "Protected by Spring Security #{auth_type}"
            elsif is_anonymous
              "Public by Spring Security anonymous"
            else
              "Public by Spring Security permitAll"
            end
          rules << {pattern: "/**", method: nil, description: "#{verb} via authorize(anyRequest)", protected_rule: protected_rule, module: module_dir, config_key: nil, path: file_path, line: line_num}
        end
      end
    end

    if any_request_covered
      block.scan(ANY_REQUEST_AUTH) do |match|
        auth_type = match[1]
        len = Math.min(120, block.bytesize - match.byte_begin(0))
        slice = block.byte_slice(match.byte_begin(0), len)
        is_anonymous = auth_type == "anonymous" ||
                       (auth_type == "hasRole" && slice.matches?(/\.\s*anyRequest\s*\(\s*\)\s*\.\s*hasRole\s*\(\s*["'](?:ROLE_)?ANONYMOUS["']\s*\)/)) ||
                       (auth_type == "hasAuthority" && slice.matches?(/\.\s*anyRequest\s*\(\s*\)\s*\.\s*hasAuthority\s*\(\s*["'](?:ROLE_)?ANONYMOUS["']\s*\)/))
        protected_rule = auth_type != "permitAll" && !is_anonymous
        rule_line = block_start_line + block[0, match.begin(1)].count('\n')
        description =
          if protected_rule
            "Protected by Spring Security #{auth_type} via anyRequest()"
          elsif is_anonymous
            "Public by Spring Security anonymous via anyRequest()"
          else
            "Public by Spring Security permitAll via anyRequest()"
          end
        rules << {pattern: "/**", method: nil, description: description, protected_rule: protected_rule, module: module_dir, config_key: nil, path: file_path, line: rule_line}
      end
    end

    if scope && !scope.empty?
      @scoped_chains << {scope: scope, order: chain_order(block), rules: rules, module: module_dir}
    else
      @security_rules.concat(rules)
    end
  end

  private def scan_form_login_rules(block : String, strings : Hash(String, String), file_path : String, block_start_line : Int32, module_dir : String?) : Array(SecurityRule)
    form_rules = [] of SecurityRule
    block.scan(FORM_LOGIN_DSL) do |match|
      open = match.byte_end(0) - 1
      open_char = block[open]
      scope = ""
      if open_char == '('
        next unless close = Noir::JSLiteralScanner.find_matching_paren_at_byte(block, open)
        inner = block.byte_slice(open + 1, close - open - 1)
        if inner.strip.empty?
          # Chained formLogin().loginPage(...).permitAll()
          rest = block.byte_slice(close + 1, block.bytesize - (close + 1))
          cut = [rest.index(".and()"), rest.index(';'), rest.index(".authorizeHttpRequests"), rest.index(".logout")].compact.min?
          scope = cut ? rest[0...cut] : rest
        else
          # Lambda formLogin(f -> f.loginPage(...).permitAll())
          scope = inner
        end
      elsif open_char == '{'
        # Kotlin DSL formLogin { loginPage = "..."; permitAll() }
        next unless close = Noir::JSLiteralScanner.find_matching_brace_at_byte(block, open)
        scope = block.byte_slice(open + 1, close - open - 1)
      end

      next unless scope.matches?(PERMIT_ALL_PATTERN)

      urls = Hash(String, String).new
      scope.scan(FORM_LOGIN_SETTER) do |setter|
        key = setter[1]
        arg_rest = scope[setter.byte_end(0)..]
        if lit = arg_rest.match(/\A\s*"([^"\\]*)"/)
          urls[key] = lit[1]
        elsif (ident = arg_rest.match(/\A\s*([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*)/)) && (str = strings[ident[1]]?)
          urls[key] = str
        end
      end

      target_urls = [] of String
      target_urls << (urls["loginPage"]? || "/login")
      if proc_url = urls["loginProcessingUrl"]?
        target_urls << proc_url
      end
      if fail_url = urls["failureUrl"]?
        target_urls << fail_url.split('?').first
      end

      rule_line = block_start_line + block[0, match.begin(0)].count('\n')
      target_urls.uniq.each do |url|
        form_rules << {
          pattern:        url,
          method:         nil,
          description:    "Public by Spring Security permitAll via formLogin()",
          protected_rule: false,
          module:         module_dir,
          config_key:     nil,
          path:           file_path,
          line:           rule_line,
        }
      end
    end
    form_rules
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
  #
  # With `java_source`, a loop variable (`for (String url : X)`,
  # `X.forEach(url -> ...)`) reads its iterable `X`, and an iterable that is
  # a `@ConfigurationProperties` list getter (`props.getUrls()`,
  # `props.getUrls().toArray(new String[0])`) adds that property's key to
  # `config_keys` instead of a pattern.
  private def matcher_patterns(args : String, strings : Hash(String, String), arrays : Hash(String, Array(String)), depth : Int32 = 0,
                               loops : Hash(String, String)? = nil, config_keys : Array(String)? = nil, java_source : String? = nil) : Array(String)
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
        elsif iterable = loops.try &.[part]?
          if values = arrays[iterable]?
            patterns.concat(values)
          elsif config_keys && java_source && (key = config_list_key(iterable, java_source))
            config_keys << key
          end
        end
      elsif config_keys && java_source && (key = config_list_key(part, java_source))
        config_keys << key
      elsif inner = part.match(INLINE_STRING_ARRAY) || part.match(MATCHER_FACTORY_CALL)
        patterns.concat(matcher_patterns(inner[1], strings, arrays, depth + 1))
      end
    end
    patterns
  end

  LOOP_HEADER              = /\A\s*(?:final\s+)?[\w$.<>\[\]]+\s+([a-z_$][\w$]*)\s*:\s*(.+?)\s*\z/m
  FOR_EACH_BINDING         = /([\w$.]+\s*\(\s*\)(?:\s*\.\s*[\w$]+\s*\(\s*\))*)\s*\.\s*forEach\s*(\()\s*\(?\s*(?:[\w$]+\s+)?([a-z_$][\w$]*)\s*\)?\s*->/
  CONFIG_LIST_GETTER       = /\A(?:this\s*\.\s*)?([a-z_$][\w$]*)\s*\.\s*(?:get([A-Z][\w$]*)|([a-z][\w$]*))\s*\(\s*\)(?:\s*\.\s*stream\s*\(\s*\))?(?:\s*\.\s*toArray\s*\([^()]*\))?\z/
  CONFIGURATION_PROPERTIES = /@ConfigurationProperties\s*\(\s*(?:(?:prefix|value)\s*=\s*)?"([^"]*)"/

  # A loop variable, its iterable expression, and the byte range of the
  # loop body where it is bound.
  alias LoopBinding = NamedTuple(variable: String, iterable: String, from: Int32, to: Int32)

  # The enhanced `for` loops and `forEach` lambdas of a chain.
  private def loop_bindings(block : String) : Array(LoopBinding)
    bindings = [] of LoopBinding
    block.scan(/\bfor\s*\(/) do |match|
      open = match.byte_end(0) - 1
      next unless close = Noir::JSLiteralScanner.find_matching_paren_at_byte(block, open)
      next unless header = block.byte_slice(open + 1, close - open - 1).match(LOOP_HEADER)
      body = close + 1
      while body < block.bytesize && block.byte_at(body).unsafe_chr.whitespace?
        body += 1
      end
      to = if body < block.bytesize && block.byte_at(body) == '{'.ord
             Noir::JSLiteralScanner.find_matching_brace_at_byte(block, body)
           else
             block.byte_index(';', body)
           end
      bindings << {variable: header[1], iterable: header[2], from: close, to: to} if to
    end
    block.scan(FOR_EACH_BINDING) do |match|
      open = match.byte_begin(2)
      next unless close = Noir::JSLiteralScanner.find_matching_paren_at_byte(block, open)
      bindings << {variable: match[3], iterable: match[1].gsub(/\s+/, ""), from: open, to: close}
    end
    bindings
  end

  # Variable => iterable for the loops whose body holds byte `offset`; an
  # inner loop's binding shadows an outer one.
  private def loops_enclosing(loops : Array(LoopBinding), offset : Int32) : Hash(String, String)
    bound = Hash(String, String).new
    loops.select { |binding| binding[:from] < offset && offset < binding[:to] }
      .sort_by! { |binding| -(binding[:to] - binding[:from]) }
      .each { |binding| bound[binding[:variable]] = binding[:iterable] }
    bound
  end

  # `prefix.property` of the `@ConfigurationProperties` list that `expr`
  # (`ignoreUrls.getUrls()`) reads in `source`: the variable's declared type
  # is resolved through the file's import or package, and that class must
  # bind a prefix and declare the property as a String collection or array.
  private def config_list_key(expr : String, source : String) : String?
    return unless match = expr.match(CONFIG_LIST_GETTER)
    variable = match[1]
    property = match[2]?.try { |getter| getter[0].downcase + getter[1..] } || match[3]
    return unless declared = source.match(/\b([A-Z][\w$]*)(?:<[^<>]*>)?\s+#{Regex.escape(variable)}\s*[;=,)]/)
    return unless file = Analyzer::Java::JavaEngine.java_type_file(declared[1], source)
    return unless (props = read_file(file)) && (bound = props.match(CONFIGURATION_PROPERTIES))
    return unless props.matches?(/\b(?:List|Set|Collection|Iterable)\s*<\s*String\s*>\s+#{Regex.escape(property)}\b|\bString\s*\[\s*\]\s+#{Regex.escape(property)}\b/)
    prefix = bound[1].strip
    prefix.empty? ? property : "#{prefix}.#{property}"
  end

  # One block per SecurityFilterChain / `configure(HttpSecurity)` and its 1-based start line.
  # The annotations right above a boundary (`@Bean @Order(1)`) belong to the
  # chain below it, so they move into its block.
  private def split_into_chain_blocks(content : String) : Array(Tuple(String, Int32))
    blocks = [] of Tuple(String, Int32)
    current = [] of String
    current_start = 1
    content.each_line do |raw|
      if raw.matches?(CHAIN_BOUNDARY) && !current.empty?
        header = [] of String
        while (last = current.last?) && (last.strip.empty? || last.lstrip.starts_with?('@'))
          header.unshift(current.pop)
        end
        blocks << {current.join("\n"), current_start} unless current.empty?
        current_start += current.size
        current = header
      end
      current << raw
    end
    blocks << {current.join("\n"), current_start} unless current.empty?
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
  #
  # The decision is made per runnable app that serves the endpoint (see
  # `serving_apps`): only the chains on that app's classpath apply, and a
  # configuration-bound list is read from that app's configuration. The
  # endpoint is guarded when any app (or any module serving it) guards it.
  # A build file is no evidence of the serving module: a framework-provided
  # route (`/actuator`) points at the parent pom that declares the
  # dependency every child app inherits.
  private def check_security_config_rules(endpoint : Endpoint) : Tuple(String, String?, Int32?)?
    modules = endpoint.details.code_paths.compact_map do |path_info|
      path = path_info.path
      build_module(path) unless MediaFilter.spec_document?(path) || File.basename(path).matches?(BUILD_FILE)
    end.uniq!
    return security_decision(endpoint, nil, nil) if modules.empty?
    modules.each do |module_dir|
      if apps = serving_apps(module_dir)
        apps.each do |app|
          if decision = security_decision(endpoint, app, module_classpath(app).try(&.[0]))
            return decision
          end
        end
      elsif decision = security_decision(endpoint, module_dir, nil)
        return decision
      end
    end
    nil
  end

  # `config_dir` holds the configuration lists are read from; `classpath`
  # (nil: unknown, every chain applies) the modules whose chains apply.
  private def security_decision(endpoint : Endpoint, config_dir : String?, classpath : Set(String)?) : Tuple(String, String?, Int32?)?
    url = endpoint.url
    applies = ->(owner : String?) { owner.nil? || classpath.nil? || classpath.includes?(owner) }
    if config_dir && classpath && @chain_modules.none? { |owner| applies.call(owner) } &&
       (@boot_apps.empty? || @boot_apps.includes?(config_dir)) && module_classpath(config_dir).try(&.[1])
      # The app declares no chain, yet Spring Security is on its classpath:
      # Boot's default chain authenticates every request.
      return {"Protected by Spring Boot default security (Spring Security on the app's classpath, no SecurityFilterChain in it)", nil, nil}
    end
    scoped = @scoped_chains.select { |chain| applies.call(chain[:module]) && chain[:scope].any? { |pattern| matches_ant_pattern?(url, pattern) } }
    rules =
      if chain = scoped.min_by? { |candidate| {candidate[:order], -candidate[:scope].max_of { |pattern| matches_ant_pattern?(url, pattern) ? pattern_specificity(pattern) : 0 }} }
        chain[:rules]
      else
        @security_rules.select { |rule| applies.call(rule[:module]) }
      end

    unresolved = [] of String
    rules = rules.flat_map do |rule|
      next [rule] unless key = rule[:config_key]
      values, note = config_dir ? module_config_list(config_dir, key) : {nil, nil}
      unless values
        unresolved << (note || key) unless rule[:protected_rule]
        next [] of SecurityRule
      end
      values.map do |pattern|
        description = rule[:protected_rule] ? "Protected by Spring Security #{rule[:description]} via #{key} (\"#{pattern}\")" : "Public by Spring Security permitAll via #{key} (\"#{pattern}\")"
        {pattern: pattern, method: rule[:method], description: description, protected_rule: rule[:protected_rule], module: rule[:module], config_key: nil, path: rule[:path], line: rule[:line]}
      end
    end

    matching = rules.select { |rule| matches_ant_pattern?(url, rule[:pattern]) }
    deciding = ->(method : String?) do
      matching.select { |rule| (rule_method = rule[:method]).nil? || rule_method == method }
        .max_by? { |rule| pattern_specificity(rule[:pattern]) }
    end
    method = endpoint.method.upcase
    best = deciding.call(method)
    note = unresolved.empty? ? "" : "; a setting can exempt paths from it: the permitAll list bound from #{unresolved.uniq.join(", ")}"
    if synthetic_any_method?(method)
      # A route serving every method (`@RequestMapping` without `method`)
      # is decided per method when a rule names one
      # (`requestMatchers(HttpMethod.GET, "/")`): say which methods the
      # decision leaves out instead of answering for all of them.
      best = deciding.call(nil)
      best_guards = best.try(&.[:protected_rule]) || false
      exceptions = matching.compact_map(&.[:method]).uniq!.compact_map do |verb|
        decision = deciding.call(verb)
        {verb, decision} if (decision.try(&.[:protected_rule]) || false) != best_guards
      end
      unless exceptions.empty?
        verbs = exceptions.map(&.[0]).join(", ")
        reasons = exceptions.compact_map { |_, decision| decision.try(&.[:description]) }.uniq!.join("; ")
        verb_form = exceptions.size == 1 ? "is" : "are"
        return {"#{best.try(&.[:description])}, except for #{verbs}, which #{verb_form} not guarded (#{reasons})#{note}", best.try(&.[:path]), best.try(&.[:line])} if best_guards
        first_guard = exceptions.compact_map { |_, decision| decision }.first?
        return {"#{reasons}, for #{verbs} only#{note}", first_guard.try(&.[:path]) || best.try(&.[:path]), first_guard.try(&.[:line]) || best.try(&.[:line])}
      end
    end
    return unless best && best[:protected_rule]

    {"#{best[:description]}#{note}", best[:path], best[:line]}
  end

  BUILD_FILE = /\A(?:pom\.xml|build\.gradle(?:\.kts)?)\z/

  # The build unit (directory of the nearest `pom.xml` / `build.gradle`)
  # holding `path`; nil when there is none.
  private def build_module(path : String) : String?
    nearest_project_root(path, BUILD_FILE)
  end

  @serving_apps = Hash(String, Array(String)?).new

  # The modules whose runtime classpath holds `module_dir`: itself and every
  # module depending on it, narrowed to the Boot entry points
  # when there are any. Nil when `module_dir` is not a Maven module.
  private def serving_apps(module_dir : String) : Array(String)?
    return @serving_apps[module_dir] if @serving_apps.has_key?(module_dir)
    @serving_apps[module_dir] = if module_classpath(module_dir)
                                  hosts = maven_modules.values.flatten.uniq!.select do |dir|
                                    module_classpath(dir).try(&.[0].includes?(module_dir))
                                  end
                                  hosts << module_dir unless hosts.includes?(module_dir)
                                  runnable = hosts.select { |dir| @boot_apps.includes?(dir) }
                                  runnable.empty? ? hosts : runnable
                                end
  end

  alias MavenDependency = NamedTuple(artifact: String, scope: String?, optional: Bool)
  alias MavenPom = NamedTuple(parent: String?, dependencies: Array(MavenDependency))

  @maven_modules : Hash(String, Array(String))? = nil
  @maven_poms = Hash(String, MavenPom?).new
  @module_classpaths = Hash(String, {Set(String), Bool}?).new

  # Comments, version pins (`dependencyManagement`), plugin dependencies
  # (`build`) and exclusions name no dependency of the module.
  MAVEN_NOISE       = /<!--.*?-->|<dependencyManagement>.*?<\/dependencyManagement>|<build>.*?<\/build>|<exclusions>.*?<\/exclusions>/m
  MAVEN_ARTIFACT_ID = /<artifactId>\s*([^<\s]+)\s*<\/artifactId>/
  MAVEN_DEPENDENCY  = /<dependency>(.*?)<\/dependency>/m
  MAVEN_PARENT      = /<parent>(.*?)<\/parent>/m

  SPRING_SECURITY_ARTIFACT = /\A(?:spring-boot-starter-security|spring-security-(?!test\z)[\w.-]+|spring-boot-starter-oauth2-[\w.-]+)\z/

  # `{module directories on module_dir's runtime classpath (itself
  # included), whether Spring Security is on it}`, by Maven's rules: a
  # parent's dependencies are the module's own; a dependency's own
  # dependencies come along unless `optional`; `test` scope never reaches
  # the runtime. Nil for a module that is not Maven.
  #
  # ponytail: Gradle modules are not followed (convention plugins and
  # `subprojects {}` can add dependencies), so they keep every chain.
  private def module_classpath(module_dir : String) : {Set(String), Bool}?
    return @module_classpaths[module_dir] if @module_classpaths.has_key?(module_dir)
    @module_classpaths[module_dir] = maven_classpath(module_dir)
  end

  private def maven_classpath(module_dir : String) : {Set(String), Bool}?
    dirs = Set(String).new
    security = false
    seen = Set({String, Bool}).new
    queue = [{module_dir, true}]
    while item = queue.shift?
      next unless seen.add?(item)
      dir, direct = item
      return unless pom = maven_pom(dir)
      dirs << dir
      pom[:parent].try { |parent| maven_modules[parent]?.try(&.each { |parent_dir| queue << {parent_dir, direct} }) }
      pom[:dependencies].each do |dependency|
        next if dependency[:scope] == "test" || (dependency[:optional] && !direct)
        security ||= dependency[:artifact].matches?(SPRING_SECURITY_ARTIFACT)
        maven_modules[dependency[:artifact]]?.try(&.each { |dependency_dir| queue << {dependency_dir, false} })
      end
    end
    {dirs, security}
  end

  private def maven_pom(dir : String) : MavenPom?
    return @maven_poms[dir] if @maven_poms.has_key?(dir)
    path = File.join(dir, "pom.xml")
    @maven_poms[dir] = if File.exists?(path) && (content = read_file(path))
                         code = content.gsub(MAVEN_NOISE, "")
                         parent = code.match(MAVEN_PARENT).try { |block| block[1].match(MAVEN_ARTIFACT_ID).try(&.[1]) }
                         dependencies = code.scan(MAVEN_DEPENDENCY).compact_map do |block|
                           next unless artifact = block[1].match(MAVEN_ARTIFACT_ID)
                           {artifact: artifact[1], scope: block[1].match(/<scope>\s*([^<\s]+)/).try(&.[1]), optional: block[1].matches?(/<optional>\s*true\s*</)}
                         end
                         {parent: parent, dependencies: dependencies}
                       end
  end

  # artifactId => directories of the project modules declaring it.
  private def maven_modules : Hash(String, Array(String))
    @maven_modules ||= begin
      index = Hash(String, Array(String)).new
      CodeLocator.instance.files_by_basename("pom.xml").each do |pom|
        next unless content = read_file(pom)
        own = content.gsub(MAVEN_NOISE, "").gsub(MAVEN_PARENT, "").match(MAVEN_ARTIFACT_ID)
        (index[own[1]] ||= [] of String) << File.dirname(Noir::PathScope.expand(pom)) if own
      end
      index
    end
  end

  CONFIG_DIRS           = {"src/main/resources", "src/main/resources/config"}
  PROFILE_CONFIG_FILE   = /\Aapplication-[^\/]+\.(?:ya?ml|properties)\z/
  INDEXED_PROPERTY_NAME = /\[\d+\]\z/
  BOOTSTRAP_CONFIG_FILE = /\Abootstrap(?:-[^\/]+)?\.(?:ya?ml|properties)\z/
  BASE_CONFIG_FILES     = %w[application.yml application.yaml application.properties]
  # Keys that pull configuration from elsewhere (another file, a config
  # server, Nacos) which can override the list.
  CONFIG_IMPORT_KEYS = %w[spring.config.import spring.config.location spring.config.additional-location]

  # The values of list property `key` in `module_dir`'s Spring Boot
  # configuration (`src/main/resources[/config]/application.{yml,yaml,properties}`),
  # by relaxed binding (`ignore-urls` binds `ignoreUrls`). Nil, with the
  # reason, when something else can decide the list: the module does not
  # set it, a profile (`application-dev.yml`, an `on-profile` document) or
  # a file beside the module (`config/application.yml`, read from the
  # working directory) sets it too, the configuration imports more
  # (`spring.config.import`, a `bootstrap.yml`), or the value is a `${...}`
  # placeholder.
  private def module_config_list(module_dir : String, key : String) : {Array(String)?, String?}
    target = relaxed_property(key)
    values : Array(String)? = nil
    CONFIG_DIRS.each do |sub|
      dir = File.join(module_dir, sub)
      next unless Dir.exists?(dir)
      children = Dir.children(dir).sort!
      if bootstrap = children.find(&.matches?(BOOTSTRAP_CONFIG_FILE))
        return {nil, "#{key}, which #{bootstrap} can import"}
      end
      BASE_CONFIG_FILES.each do |name|
        path = File.join(dir, name)
        next unless File.exists?(path) && (content = read_file(path))
        properties = name.ends_with?(".properties")
        if CONFIG_IMPORT_KEYS.any? { |import| config_file_values(content, properties, relaxed_property(import))[0] }
          return {nil, "#{key}, which a spring.config import in #{name} can override"}
        end
        base, profiled = config_file_values(content, properties, target)
        return {nil, "#{key}, which a profile document in #{name} also sets"} if profiled
        values = base if base
      end
      children.each do |name|
        next unless name.matches?(PROFILE_CONFIG_FILE) && (content = read_file(File.join(dir, name)))
        base, profiled = config_file_values(content, name.ends_with?(".properties"), target)
        return {nil, "#{key}, which #{name} also sets"} if base || profiled
      end
    end
    {module_dir, File.join(module_dir, "config")}.each do |dir|
      (Dir.children(dir).sort! rescue [] of String).each do |name|
        next unless BASE_CONFIG_FILES.includes?(name) || name.matches?(PROFILE_CONFIG_FILE)
        next unless content = read_file(File.join(dir, name))
        base, profiled = config_file_values(content, name.ends_with?(".properties"), target)
        return {nil, "#{key}, which #{File.basename(dir) == "config" ? "config/" : ""}#{name} beside the module also sets"} if base || profiled
      end
    end
    return {nil, "#{key}, set from a ${...} placeholder"} if values.try &.any?(&.includes?("${"))
    {values, nil}
  end

  # `{the value the file's default documents set, whether a profile document sets it}`.
  private def config_file_values(content : String, properties : Bool, target : String) : {Array(String)?, Bool}
    return {properties_list(content, target), false} if properties

    found = nil
    profiled = false
    YAML.parse_all(content).each do |document|
      next unless value = yaml_property(document, target)
      if yaml_property(document, "spring.config.activate.onprofile") || yaml_property(document, "spring.profiles")
        profiled = true
      else
        found = value
      end
    end
    {found, profiled}
  rescue
    # An unreadable file may set it: treat it as undecided.
    {nil, true}
  end

  # `key=a,b` or `key[0]=a` lines of a `.properties` file.
  private def properties_list(content : String, target : String) : Array(String)?
    found = nil
    content.each_line do |line|
      stripped = line.strip
      next if stripped.empty? || stripped.starts_with?('#') || stripped.starts_with?('!')
      next unless separator = stripped.index(/[=:]/)
      name = stripped[...separator].strip
      next unless relaxed_property(name.sub(INDEXED_PROPERTY_NAME, "")) == target
      value = stripped[(separator + 1)..].strip
      if name.matches?(INDEXED_PROPERTY_NAME)
        (found ||= [] of String) << value
      else
        found = value.split(',').map(&.strip).reject(&.empty?)
      end
    end
    found
  end

  private def yaml_property(node : YAML::Any, target : String, prefix : String = "") : Array(String)?
    return unless hash = node.as_h?
    hash.each do |name, value|
      path = prefix.empty? ? name.to_s : "#{prefix}.#{name}"
      relaxed = relaxed_property(path)
      if relaxed == target
        # A mapping (`spring.profiles: {active: dev}`) is not a list value.
        return if value.as_h?
        return value.as_a.compact_map { |item| yaml_text(item) } if value.as_a?
        return (yaml_text(value) || "").split(',').map(&.strip).reject(&.empty?)
      elsif target.starts_with?("#{relaxed}.")
        if found = yaml_property(value, target, path)
          return found
        end
      end
    end
    nil
  end

  private def yaml_text(node : YAML::Any) : String?
    case raw = node.raw
    when String, Int64, Float64, Bool then raw.to_s
    end
  end

  private def relaxed_property(name : String) : String
    name.downcase.delete("-_")
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

  private def check_annotations(ctx : SourceContext, method : String) : SecurityAnnotation?
    line = ctx.line
    return unless line

    # `@PostAuthorize` is evaluated after the handler returns: it hides a
    # read's result, but a write has already happened when it refuses.
    post_ok = SAFE_HTTP_METHODS.includes?(method.upcase)
    class_names = post_ok ? CLASS_ANNOTATION_NAMES : CLASS_ANNOTATION_NAMES - ["@PostAuthorize"]
    metas = @security_meta_annotations.values
    metas.reject!(&.spring_annotation.==("@PostAuthorize")) unless post_ok

    # Walk backwards from endpoint line to find annotations
    # `line` is 1-indexed (from PathInfo), array is 0-indexed
    lines = ctx.lines
    endpoint_idx = line - 1
    found = [] of SecurityAnnotation

    idx = [endpoint_idx - 1, lines.size - 1].min
    while idx >= 0 && idx >= endpoint_idx - 15
      current_line = code_line(lines[idx])
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

      if item = line_security_annotation(current_line, post_ok, metas, false)
        found << item
      end

      idx -= 1
    end

    annotation_lines_below(lines, endpoint_idx, "@").each do |below|
      if item = line_security_annotation(code_line(below), post_ok, metas, false)
        found << item
      end
    end

    if picked = pick_security_annotation(found)
      return picked
    end

    # A controller-level `@PreAuthorize`/`@Secured`/`@RolesAllowed` applies to
    # every handler the class declares. The walk above cannot reach it — it
    # stops at the `public`/`class` boundary by design, so a handler under an
    # `@PreAuthorize("hasRole('ADMIN')")` controller was reported as
    # unauthenticated. Check the class declaration separately.
    class_found = [] of SecurityAnnotation
    class_names.each do |annotation_name|
      if class_line = class_level_annotation(ctx.path, lines, annotation_name)
        if item = line_security_annotation(code_line(class_line), post_ok, metas, true)
          class_found << item
        end
      end
    end

    metas.each do |meta|
      # The lookup matches by prefix: `@Admin` must not take `@AdminApi`.
      if class_level_annotation(ctx.path, lines, "@#{meta.name}").try { |raw| code_line(raw).matches?(/\A@#{Regex.escape(meta.name)}\b/) }
        class_found << {
          public_access: false,
          description:   "Protected by Spring #{meta.spring_annotation} (@#{meta.name}) on the controller class",
        }
      end
    end

    pick_security_annotation(class_found)
  end

  private def code_line(raw : String) : String
    Noir::CComments.strip(raw).strip
  end

  # `public_access` is a whole-expression anonymous rule (`permitAll()`,
  # `@Secured("IS_AUTHENTICATED_ANONYMOUSLY")`). A restricting annotation on
  # the same member wins. An argument we cannot read stays a guard.
  private def line_security_annotation(line : String, post_ok : Bool, metas : Array(MetaAnnotation), on_class : Bool) : SecurityAnnotation?
    if match = line.match(/@((?:[\w$]+\.)*?(PreAuthorize|PostAuthorize|Secured|RolesAllowed))\b/)
      simple = match[2]
      return if simple == "PostAuthorize" && !post_ok
      suffix = on_class ? " on the controller class" : ""
      admits = annotation_admits_anonymous?(simple, annotation_argument(line, simple))
      return {public_access: admits, description: "Protected by Spring @#{match[1]}#{suffix}"}
    end

    metas.each do |meta|
      next unless line.matches?(/(?:\A|[^@\w])@#{Regex.escape(meta.name)}\b/)
      suffix = on_class ? " on the controller class" : ""
      return {public_access: false, description: "Protected by Spring #{meta.spring_annotation} (@#{meta.name})#{suffix}"}
    end
    nil
  end

  private def annotation_argument(line : String, name : String) : String?
    start = line.index(/@[\w$.]*#{Regex.escape(name)}\b/)
    return unless start
    open = line.index('(', start)
    return unless open
    depth = 0
    idx = open
    while idx < line.size
      case line[idx]
      when '('
        depth += 1
      when ')'
        depth -= 1
        return line[(open + 1)...idx] if depth == 0
      end
      idx += 1
    end
    nil
  end

  private def annotation_admits_anonymous?(name : String, arg : String?) : Bool
    case name
    when "RolesAllowed"
      false
    when "Secured"
      secured_admits_anonymous?(arg)
    else
      return false unless arg
      expression_of(arg).matches?(PUBLIC_SPEL)
    end
  end

  private def expression_of(arg : String) : String
    if quoted = arg.match(/"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'/)
      (quoted[1]? || quoted[2]?).to_s
    else
      arg.strip
    end
  end

  private def secured_admits_anonymous?(arg : String?) : Bool
    return false unless arg
    roles = [] of String
    arg.scan(/"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'/) do |match|
      roles << (match[1]? || match[2]?).to_s
    end
    return false if roles.empty?
    roles.all? { |role| ANONYMOUS_ROLES.includes?(role) }
  end

  private def pick_security_annotation(found : Array(SecurityAnnotation)) : SecurityAnnotation?
    found.find { |item| !item[:public_access] } || found.first?
  end

  private def check_endpoint(endpoint : Endpoint)
    # The login / logout / OAuth2 filters answer before any authorization rule.
    return if endpoint.tags.includes?(Analyzer::Java::JavaEngine::SECURITY_FILTER_TAG)

    # Phase 2: Check annotations near code_paths. A public annotation does
    # not stop the URL-rule and in-handler checks, and it is recorded as
    # anonymous so a name-only source scan does not put the guard back.
    annotation_public = false
    contexts = read_source_context(endpoint)
    contexts.each do |ctx|
      decision = check_annotations(ctx, endpoint.method)
      next unless decision
      if decision[:public_access]
        annotation_public = true
      else
        endpoint.add_tag(Tag.new("auth", decision[:description], "spring_auth"))
        return
      end
    end

    # Phase 3: Match endpoint URL against security config rules
    if decision = check_security_config_rules(endpoint)
      description, rule_path, rule_line = decision
      endpoint.add_tag(Tag.new("auth", description, "spring_auth", rule_path, rule_line))
      note_public_annotation(endpoint) if annotation_public
      return
    end

    # Phase 4: Match endpoint URL against registered HandlerInterceptors
    if decision = check_interceptor_rules(endpoint)
      description, rule_path, rule_line = decision
      endpoint.add_tag(Tag.new("auth", description, "spring_auth", rule_path, rule_line))
      note_public_annotation(endpoint) if annotation_public
      return
    end

    # Phase 4b: Match endpoint URL against registered servlet filters
    if decision = check_servlet_filter_rules(endpoint)
      description, rule_path, rule_line = decision
      endpoint.add_tag(Tag.new("auth", description, "spring_auth", rule_path, rule_line))
      note_public_annotation(endpoint) if annotation_public
      return
    end

    # Phase 5: a handler that refuses an anonymous caller itself.
    contexts.each do |ctx|
      if description = anonymous_refusal(ctx)
        endpoint.add_tag(Tag.new("auth", description, "spring_auth"))
        note_public_annotation(endpoint) if annotation_public
        return
      end
    end

    note_public_annotation(endpoint) if annotation_public
  end

  private def note_public_annotation(endpoint : Endpoint)
    endpoint.add_tag(Tag.new("anonymous", "Spring security annotation admits anonymous callers", "spring_auth"))
  end

  private def check_interceptor_rules(endpoint : Endpoint) : Tuple(String, String, Int32)?
    return if @registered_interceptors.empty?
    per_serving_classpath(endpoint) { |classpath| interceptor_decision(endpoint, classpath) }
  end

  private def check_servlet_filter_rules(endpoint : Endpoint) : Tuple(String, String, Int32)?
    return if @servlet_filters.empty?
    per_serving_classpath(endpoint) { |classpath| servlet_filter_decision(endpoint, classpath) }
  end

  # The first decision of the block for the runtime classpath of each app
  # serving `endpoint` (nil: unknown, everything applies).
  private def per_serving_classpath(endpoint : Endpoint, & : Set(String)? -> Tuple(String, String, Int32)?) : Tuple(String, String, Int32)?
    modules = endpoint.details.code_paths.compact_map do |path_info|
      path = path_info.path
      build_module(path) unless MediaFilter.spec_document?(path) || File.basename(path).matches?(BUILD_FILE)
    end.uniq!

    return yield nil if modules.empty?

    modules.each do |module_dir|
      if apps = serving_apps(module_dir)
        apps.each do |app|
          if desc = yield module_classpath(app).try(&.[0])
            return desc
          end
        end
      elsif desc = yield Set{module_dir}
        return desc
      end
    end
    nil
  end

  private def interceptor_decision(endpoint : Endpoint, classpath : Set(String)?) : Tuple(String, String, Int32)?
    url = endpoint.url
    applies = ->(owner : String?) { owner.nil? || classpath.nil? || classpath.includes?(owner) }

    @registered_interceptors.each do |reg|
      next unless applies.call(reg.module_dir)

      interceptor = @interceptor_defs[reg.interceptor_name]?
      if interceptor.nil?
        if entry = @interceptor_defs.find { |k, _| k.downcase == reg.interceptor_name.downcase }
          interceptor = entry[1]
        end
      end
      next unless interceptor && interceptor.is_auth_guard

      matches_add = reg.add_patterns.any? { |pattern| matches_ant_pattern?(url, pattern) }
      next unless matches_add

      matches_exclude = reg.exclude_patterns.any? { |pattern| matches_ant_pattern?(url, pattern) }
      next if matches_exclude

      return {"Protected by Spring HandlerInterceptor #{interceptor.name}", reg.file_path, reg.line}
    end
    nil
  end

  HANDLER_PRINCIPAL_PARAM = /(?:\b(?:java\.security\.)?(?:Principal|Authentication)\s+([a-z_$][\w$]*)\s*[,)]|@AuthenticationPrincipal\s+(?:final\s+)?[\w$.<>?]+\s+([a-z_$][\w$]*)\s*[,)]|\b([a-z_][\w]*)\s*:\s*(?:java\.security\.)?(?:Principal|Authentication)\?)/
  # A refusal written as code: an unauthorized/forbidden factory or status,
  # a 401/403 literal, an access-denied exception.
  REFUSING_RETURN = /\b(?:unauthori[sz]ed|forbidden|denied|40[13])\b/i
  REDIRECT_LOGIN  = /"redirect:[^"]*\blogin\b/i

  # "Protected by ..." when the handler at `ctx` takes the caller's
  # `Principal` / `Authentication` and its body opens with a refusal for a
  # null one: `if (principal == null) return CommonResult.unauthorized(..)`,
  # a `throw`, or a redirect to a login page. A whitelisted route can still
  # turn anonymous callers away this way; a check after other statements
  # (a side effect already ran) or inside a lambda is not read.
  private def anonymous_refusal(ctx : SourceContext) : String?
    return unless (line = ctx.line) && line >= 1
    return unless ctx.path.ends_with?(".java") || ctx.path.ends_with?(".kt")
    raw = Noir::CComments.strip(ctx.lines[(line - 1), 80].join("\n"))
    code = raw.gsub(STRING_LITERAL) { |literal| "#{literal[0]}#{" " * (literal.size - 2)}#{literal[-1]}" }
    return unless open = method_body_open(code)
    return unless param = code[0, open].match(HANDLER_PRINCIPAL_PARAM)
    name = param[1]? || param[2]? || param[3]
    escaped = Regex.escape(name)
    return unless check = code[(open + 1)..].match(/\A\s*if\s*\(\s*(?:#{escaped}\s*==\s*null|null\s*==\s*#{escaped})\s*\)\s*\{?\s*(return|throw)\b/)
    if check[1] == "return"
      start = open + 1 + check.end(0)
      return unless stop = code.index(';', start)
      return unless code[start...stop].matches?(REFUSING_RETURN) || raw[start...stop].matches?(REDIRECT_LOGIN)
    end
    "Protected by in-handler check: refuses an anonymous caller (#{name} == null)"
  end

  # Index of the `{` opening the method body in `text` (annotations, then
  # the declaration): the first brace outside parentheses, so an
  # annotation's `{"/a", "/b"}` array is skipped. Nil for a declaration
  # without a block body (`String x();`, Kotlin `fun x() = ...`).
  private def method_body_open(text : String) : Int32?
    depth = 0
    text.each_char_with_index do |char, index|
      case char
      when '('      then depth += 1
      when ')'      then depth -= 1
      when '{'      then return index if depth == 0
      when ';', '=' then return if depth == 0
      end
    end
    nil
  end
end
