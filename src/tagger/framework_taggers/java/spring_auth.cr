require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../miniparsers/java_route_extractor_ts"
require "../../../utils/js_literal_scanner"
require "../../../utils/top_level_split"
require "../../../analyzer/engines/java_engine"
require "../../../analyzer/engines/kotlin_engine"
require "../../../utils/xml_comments"
require "./spring_module_scope"

@[Noir::TaggerFor(key: "spring_auth", name: "Spring Auth Tagger", desc: "Identifies Spring Security patterns (annotations, security config)", order: 20)]
class SpringAuthTagger < FrameworkTagger
  include SpringModuleScope

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
  # `doFilter` does not plainly turn a caller without a credential away.
  # `required` / `excluded` are the paths its `shouldNotFilter` and
  # pass-through branches leave it on: every set in `required` must hold a
  # test the URL passes, and no `excluded` one may. `settings` say how a
  # setting can lift it.
  record ServletFilterDef,
    name : String,
    file_path : String,
    line : Int32,
    module_dir : String?,
    package_name : String,
    refusal : String?,
    component : Bool,
    web_filter_patterns : Array(String)?,
    required : Array(Array(PathTest)),
    excluded : Array(PathTest),
    settings : Array(String)

  # A `FilterRegistrationBean`: `names` are the filter types it may hold,
  # `patterns` its servlet URL patterns (nil: one noir cannot read),
  # `settings` the properties it is registered under.
  record ServletFilterRegistration,
    names : Array(String),
    file_path : String,
    line : Int32,
    patterns : Array(String)?,
    enabled : Bool,
    module_dir : String?,
    settings : Array(String)

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
  RULE_AFTER_CALL  = /\A\s*\.\s*(permitAll|anonymous|denyAll|authenticated|fullyAuthenticated|hasRole|hasAnyRole|hasAuthority|hasAnyAuthority|access)\s*(?:\(|\{)/
  ANY_REQUEST_AUTH = /\.\s*any(?:Request|Exchange)\s*\(\s*\)\s*\.\s*(permitAll|anonymous|denyAll|authenticated|fullyAuthenticated|hasRole|hasAnyRole|hasAuthority|hasAnyAuthority|access)\s*(?:\(|\{)/

  # The Kotlin DSL Spring Security documents for Kotlin apps:
  # `authorizeHttpRequests { authorize("/public/**", permitAll);
  # authorize(anyRequest, authenticated) }` (`anyExchange` in WebFlux).
  KOTLIN_AUTHORIZE_RULE = /\bauthorize\s*\(\s*(?:HttpMethod\.(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s*,\s*)?(?:"([^"]+)"|(any(?:Request|Exchange)))\s*,\s*(permitAll|anonymous|denyAll|authenticated|fullyAuthenticated|hasRole|hasAnyRole|hasAuthority|hasAnyAuthority|access)\b/

  FORM_LOGIN_DSL     = /(?:\.\s*formLogin\s*\(|\bformLogin\s*\(|\bformLogin\s*\{)/
  FORM_LOGIN_SETTER  = /\b(loginPage|loginProcessingUrl|failureUrl)\s*(?:\(\s*|=\s*)/
  PERMIT_ALL_PATTERN = /\bpermitAll\s*\(\s*(?:true\s*)?\)/

  ORDER_ANNOTATION  = /@Order\s*\(\s*(?:value\s*=\s*)?(-?\d+|Ordered\.HIGHEST_PRECEDENCE|Ordered\.LOWEST_PRECEDENCE)\s*\)/
  CHAIN_BOUNDARY    = /Security(?:Web)?FilterChain\b|configure\s*\(\s*(?:final\s+)?HttpSecurity/
  CHAIN_DECLARATION = /\b(?:SecurityFilterChain|SecurityWebFilterChain|WebSecurityConfigurerAdapter)\b|configure\s*\(\s*(?:final\s+)?(?:Server)?HttpSecurity/
  # A chain's authorization DSL: a chain that has one yet yields no rule
  # noir can read is a configuration it does not read.
  # A `SecurityConfigurer` bean (`http -> http.authorizeExchange(..)`): a
  # chain assembled from configurers, with no chain method of its own.
  SECURITY_CONFIGURER_LAMBDA = /\bhttp\s*->\s*http\s*\.\s*(?:authorizeExchange|authorizeHttpRequests|authorizeRequests)\b/
  ACCESS_NEG_AUTH            = /!\s*[\w$.]*\b(?:isAuthenticated|isFullyAuthenticated)\s*\(/
  ACCESS_NEG_ANON            = /!\s*[\w$.]*\bisAnonymous\s*\(/
  ACCESS_ANON                = /\bisAnonymous\s*\(/
  ACCESS_AUTH                = /\b(?:isAuthenticated|isFullyAuthenticated)\b/
  ACCESS_TYPE_TEST           = /\bisInstance\b|\binstanceof\b/
  ACCESS_NOTE                = "; a custom authorization manager decides, and the roles or permissions it reads can admit anonymous callers"
  AUTHORIZATION_DSL          = /\b(?:authorizeHttpRequests|authorizeRequests|authorizeExchange)\b/
  # Spring Security switched on without a chain of the app's own: its
  # default chain authenticates every request.
  ENABLE_SECURITY = /@Enable(?:Web|WebFlux|RSocket)Security\b/
  # An XML `<http>` element in the Spring Security namespace.
  XML_SECURITY_NAMESPACE = "springframework.org/schema/security"
  XML_HTTP_ELEMENT       = /<(?:[\w-]+:)?http[\s>]/
  XML_HTTP_TAG           = /<(?:[\w-]+:)?http(?:\s[^>]*)?>/
  XML_SECURITY_NONE      = /\bsecurity\s*=\s*"none"/
  XML_ACCESS             = /\baccess\s*=\s*"([^"]*)"/
  XML_PUBLIC_ACCESS      = /\A(?:permitAll(?:\(\))?|IS_AUTHENTICATED_ANONYMOUSLY|isAnonymous\(\))\z/
  # An authorization noir does not read off `access` attributes.
  XML_OTHER_AUTHORIZATION = /<(?:[\w-]+:)?custom-filter\b|\b(?:access-decision-manager|authorization-manager)-ref\s*=/

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
  alias UnreadConfig = NamedTuple(module: String?, what: String, path: String, line: Int32)

  alias ScopedChain = NamedTuple(scope: Array(String), order: Int32, rules: Array(SecurityRule), module: String?)

  def initialize(options : Hash(String, YAML::Any))
    super
    # Rules of the chains that serve every request (and of chains scoped by
    # a matcher noir cannot read, which keep the old global treatment).
    @security_rules = [] of SecurityRule
    @scoped_chains = [] of ScopedChain
    # Build units that declare a security chain (nil: a file outside any).
    @chain_modules = Set(String?).new
    # Build units that switch Spring Security on (`@EnableWebSecurity`), and
    # security configurations noir does not read (an XML `<http>`, a chain
    # whose authorization rules it cannot read).
    @security_enabled = Set(String?).new
    @unread_configs = [] of UnreadConfig
    @security_meta_annotations = Hash(String, MetaAnnotation).new
    @interceptor_defs = Hash(String, InterceptorDef).new
    @registered_interceptors = [] of RegisteredInterceptor
    # Filter state is per build unit: classes of one simple name may live in two apps.
    @servlet_filters = [] of ServletFilterDef
    @filter_registrations = [] of ServletFilterRegistration
    @bean_types = Set({String?, String}).new
    @servlet_component_scans = Set(String?).new
    @scan_packages = Hash(String, Array(String)).new
    @scan_imports = Hash(String, Array(String)).new
    @scan_excludes = Hash(String, Array(String)).new
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
    @security_enabled.clear
    @unread_configs.clear
    @boot_apps.clear
    @security_meta_annotations.clear
    @interceptor_defs.clear
    @registered_interceptors.clear
    @servlet_filters.clear
    @filter_registrations.clear
    @bean_types.clear
    @servlet_component_scans.clear
    @scan_packages.clear
    @scan_imports.clear
    @scan_excludes.clear
    @context_paths.clear

    # Find Java and Kotlin security config files
    extensions = [".java", ".kt"]
    extensions.each do |ext|
      files = collect_files_by_extension(ext)
      files.each do |file|
        content = read_file(file)
        next if content.nil?
        note_boot_app(file, content)
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

        unless test_source?(file)
          @security_enabled << module_dir if content.matches?(ENABLE_SECURITY) && Noir::CComments.strip(content).matches?(ENABLE_SECURITY)
          scan_servlet_filter_defs(content, file, module_dir) if content.includes?("doFilter")
          scan_filter_registrations(content, file, module_dir) if content.includes?("FilterRegistrationBean")
          scan_bean_types(content, module_dir) if content.includes?("@Bean")
          @servlet_component_scans << module_dir if content.includes?("@ServletComponentScan")
          scan_component_packages(content, module_dir) if module_dir && (content.includes?("@SpringBootApplication") || content.includes?("@ComponentScan") || content.includes?("@Import"))
        end

        next unless content.includes?("SecurityFilterChain") || content.includes?("HttpSecurity") || content.includes?("WebSecurityConfigurerAdapter") || content.matches?(SECURITY_CONFIGURER_LAMBDA)
        # A test class builds its own throwaway chain; it secures no served endpoint.
        next if test_source?(file)

        scan_security_config(content, file.ends_with?(".java"), module_dir, file)
      end
    end

    collect_files_by_extension(".xml").each do |file|
      next if test_source?(file)
      next unless (content = read_file(file)) && content.includes?(XML_SECURITY_NAMESPACE)
      xml = Noir::XmlComments.strip(content)
      next unless http = xml.match(XML_HTTP_ELEMENT)
      # An `<http>` is a chain: Boot's default one backs off. Every `<http>`
      # `security="none"`, or only permitAll rules, guards nothing.
      module_dir = build_module(file)
      @chain_modules << module_dir if module_dir
      accesses = xml.scan(XML_ACCESS).map(&.[1].strip)
      next if xml.scan(XML_HTTP_TAG).all?(&.[0].matches?(XML_SECURITY_NONE)) ||
              (!accesses.empty? && accesses.all?(&.matches?(XML_PUBLIC_ACCESS)) && !xml.matches?(XML_OTHER_AUTHORIZATION))
      @unread_configs << {module: module_dir, what: "the XML <http> configuration", path: file, line: xml[0, http.begin(0)].count('\n') + 1}
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
  # A 401/403 status handed to a response helper (`writeError(res, SC_UNAUTHORIZED)`).
  REFUSAL_STATUS_CONSTANT = /\b(?:HttpServletResponse\.)?SC_(?:UNAUTHORIZED|FORBIDDEN)\b|\bHttpStatus\.(?:UNAUTHORIZED|FORBIDDEN)\b/
  # A statement that is one call (`sendUnauthorized(res)`, `throw ForbiddenException()`), and its name.
  STATEMENT_CALL = /\A(?:return\s+|throw\s+(?:new\s+)?)?(?:[\w$]+\s*(?:\(\s*\))?\s*\.\s*)*([\w$]+)\s*\(/
  # Filters that refuse for another reason than a missing credential.
  # ponytail: a name list; a filter named for its credential check is not read further.
  NON_AUTH_FILTER_NAME = /Csrf|Xsrf|Origin|Refer|RateLimit|Throttl|Cors|Xss/i
  # Reading what the caller presents as a credential. Without one, a filter
  # that refuses with 403 checks something else (a Referer allowlist, an IP).
  FILTER_CREDENTIAL_READ = /\bget(?:Header|Parameter)\s*\(\s*(?:HttpHeaders\.AUTHORIZATION\b|"[^"]*(?:auth|token|key|jwt|bearer|session|credential)[^"]*"|[\w$.]*(?:auth|token|key|jwt|session)[\w$]*(?:\s*\(\s*\))?\s*\))|\bgetSession\s*\(|\brequest\.session\b|\b(?:getUserPrincipal|userPrincipal|getRemoteUser|remoteUser|SecurityContextHolder)\b|\bgetCookies\s*\(|\.cookies\b|\b\w*(?:token|auth|jwt|session|credential|principal)\w*\s*\(\s*(?:request|req|httpRequest|httpServletRequest|servletRequest)\b[^()]*\)/i
  # A credential read with its receiver (`request.getHeader("X-Api-Key")`).
  CREDENTIAL_EXPRESSION = /(?:[\w$]+\s*\.\s*)*(?:#{FILTER_CREDENTIAL_READ.source})/i
  # A credential local whose value for a missing credential is not plain:
  # it tests for null or emptiness itself, or falls back with `?:` / a ternary.
  MURKY_VALUE = /\bnull\b|\?:|\s\?\s|\|\||&&|\b(?:isEmpty|isBlank|isNullOrEmpty|isNullOrBlank|hasText|hasLength|isNotEmpty|isNotBlank|orElse\w*|getOrDefault|ifEmpty|default\w*|requireNonNullElse\w*|firstNonNull|Objects\.toString)\b/
  # A field holding configuration: `@Value`-injected, or typed `*Properties` / `*Config`.
  CONFIG_FIELD_TYPE = /(?:Properties|Config|Configuration|Settings)\??\z/
  # Reads of the current request that do not name the request parameter.
  REQUEST_HOLDER = /\b(?:RequestContextHolder|RequestAttributes|ServletRequestAttributes|HttpServletRequest|currentRequest)\b/
  # `path.startsWith("/admin")`, `request.servletPath == "/login"`.
  PATH_TEST = /(!\s*)?((?:[\w$]+(?:\s*\(\s*\))?\s*\.\s*)*[\w$]+(?:\s*\(\s*\))?)\s*(?:\.\s*(startsWith|equals)\s*\(\s*"(\/[^"]*)"\s*\)|(==|!=)\s*"(\/[^"]*)")/
  # `request.requestURI in OPEN`, `OPEN.contains(uri)` over a field of literals.
  MEMBERSHIP_TEST = /(!\s*)?(?:(?:[\w$]+(?:\s*\(\s*\))?\s*\.\s*)*[\w$]+(?:\s*\(\s*\))?\s+(!?in)\s+([A-Za-z_$][\w$]*)\b(?!\s*[.(])|([A-Za-z_$][\w$]*)\s*\.\s*contains\s*\(\s*(?:[\w$]+(?:\s*\(\s*\))?\s*\.\s*)*[\w$]+(?:\s*\(\s*\))?\s*\))/
  # A bean or filter registered only under a property or profile.
  CONDITIONAL_REGISTRATION = /@(?:ConditionalOn\w+|Profile)\b(?:\s*\([^()]*\))?/
  IDENTIFIER               = /[A-Za-z_$][\w$]*/

  # How a block of a filter treats a caller who presents no credential.
  enum Walk
    Guard   # refused, and the request stops there
    Refused # refused, but control leaves the block's end: what follows decides
    Pass    # handed on (`chain.doFilter`)
    Through # neither: control leaves the block's end
    Unknown
  end

  # What a condition is for a caller without a credential: true, false,
  # unknown, or `limited` to the paths of `tests` (the same shape as
  # `path_tests`) and the settings named in `settings`.
  record CondVerdict,
    kind : Symbol,
    tests : Array({Array(PathTest), Bool}) = [] of {Array(PathTest), Bool},
    settings : Array(String) = [] of String

  # The names of one filter method and what the walk found so far.
  class FilterReading
    getter tainted : Set(String)
    getter credential : Set(String)
    # Credential locals whose value for a missing credential noir cannot
    # tell (`ok = token == null || valid(token)`, reassigned, `?: true`).
    getter murky : Set(String)
    getter body : String
    getter helpers : Hash(String, String)
    getter declared : Set(String)
    getter required = [] of Array(PathTest)
    getter excluded = [] of PathTest
    getter settings = [] of String

    def initialize(@tainted, @credential, @murky, @body, @helpers, @declared)
    end
  end

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
        package_name: clean.match(/^\s*package\s+([\w.]+)/m).try(&.[1]) || "",
        refusal: nil,
        component: lead.matches?(/@Component\b/),
        web_filter_patterns: web_filter_patterns(lead),
        required: [] of Array(PathTest),
        excluded: [] of PathTest,
        settings: lead.scan(CONDITIONAL_REGISTRATION).map { |found| "it is registered only under `#{found[0]}`" }
      )
      @servlet_filters << (judge_servlet_filter(filter, body) || filter)
    end
  end

  # `filter` with its refusal, the paths its pass-throughs leave it on and
  # the settings that can lift it, read from its class `body`; nil when it
  # is not plainly an auth guard: when a caller without a credential can
  # reach `chain.doFilter` (or the handler) on any path or condition noir
  # cannot read.
  private def judge_servlet_filter(filter : ServletFilterDef, body : String) : ServletFilterDef?
    return if filter.name.matches?(NON_AUTH_FILTER_NAME) || body.matches?(/csrf|xsrf/i) || !body.matches?(FILTER_CREDENTIAL_READ)
    return unless decl = body.match(DO_FILTER_DECLARATION)
    return unless params = paren_inner(body, decl.byte_end(0) - 1)
    return unless open = body.byte_index('{', params[1])
    return unless close = Noir::JSLiteralScanner.find_matching_brace_at_byte(body, open)
    method = body.byte_slice(open + 1, close - open - 1)

    helpers, declared = refusing_helpers(body)
    tainted, credential, murky = request_names(params[0], method)
    reading = FilterReading.new(tainted, credential, murky, body, helpers, declared)
    walk, refusal = walk_block(method, reading)
    # A refusal at the end of doFilter stops the request as well.
    return unless (walk.guard? || walk.refused?) && refusal

    if skip = body.match(SHOULD_NOT_FILTER)
      return unless read_should_not_filter(body, skip, reading)
    end

    filter.copy_with(refusal: refusal_code(refusal), required: reading.required, excluded: reading.excluded,
      settings: filter.settings + reading.settings.map { |cond| "it hands the request on unchecked when `#{cond.gsub(/\s+/, " ")}`" })
  end

  private def refusal_code(text : String) : String
    if text.matches?(/401|UNAUTHORI[SZ]ED/i)
      "401"
    elsif text.matches?(/403|FORBIDDEN/i)
      "403"
    else
      text.match(/(?:new\s+)?([A-Z][\w$]*)/).try(&.[1]) || "an exception"
    end
  end

  # Walks the statements of `code` in order for a caller without a
  # credential. The first one that hands the request on (Pass) decides, or
  # a refusal followed by `return` / `throw` (Guard); a refusal that control
  # runs past is Refused, and a later `chain.doFilter` means the handler
  # runs anyway. An if/else chain, `when`, or `try` is decided by the
  # branch that caller takes.
  private def walk_block(code : String, reading : FilterReading) : {Walk, String?}
    masked = mask_literals(code)
    refused = nil
    each_statement(masked) do |start, stop|
      text = code[start...stop]
      head = masked[start...stop]
      stops = head.matches?(/\A(?:return|throw)\b/)
      verdict = if head.matches?(/\Aif\s*\(/)
                  walk_branches(if_branches(text), reading)
                elsif head.matches?(/\Atry\b/)
                  walk_try(text, reading)
                elsif head.matches?(/\Awhen\b/)
                  (branches = when_branches(text)) ? walk_branches(branches, reading) : {Walk::Unknown, nil}
                elsif head.matches?(/\A(?:for|while|do|switch|synchronized)\b/)
                  head.includes?("doFilter") || refusal_in(head, reading) ? {Walk::Unknown, nil} : {Walk::Through, nil}
                elsif head.matches?(/\A(?:return\s+)?(?:[\w$]+\s*\.\s*)+doFilter\s*\(/)
                  {Walk::Pass, nil}
                elsif found = refusal_in(head, reading)
                  statement_refusal(head, found)
                elsif refused && stops
                  {Walk::Guard, refused}
                elsif head.includes?("doFilter") || stops
                  {Walk::Unknown, nil}
                else
                  {Walk::Through, nil}
                end
      case verdict[0]
      when .through?
        next
      when .refused?
        refused ||= verdict[1]
        next
      when .guard?
        return verdict
      else
        # After a refusal, the handler still runs: no guard.
        return refused ? {Walk::Unknown, nil} : verdict
      end
    end
    refused ? {Walk::Refused, refused} : {Walk::Through, nil}
  end

  # A statement holding refusal `found`: Guard when it also stops the
  # request (`throw ..`, `return sendError(..)`, Kotlin `?: run { ..; return }`),
  # Refused when control goes on; Unknown when the refusal sits in a lambda
  # or block that a missing credential may never run (`?.let { .. }`, `ifPresent(t -> ..)`).
  private def statement_refusal(head : String, found : String) : {Walk, String?}
    at = head.index(found) || 0
    before = head[0, at]
    nested = before.includes?("->") || before.count('{') > before.count('}')
    if nested
      return {Walk::Unknown, nil} unless elvis = before.index("?:")
      after = head[(elvis + 2)..]
      return {Walk::Unknown, nil} unless after.matches?(/\A\s*(?:run\s*)?\{/) && after.matches?(/\breturn\b/)
      return {Walk::Unknown, nil} if before[0, elvis].includes?("->") || before[0, elvis].count('{') > before[0, elvis].count('}')
      return {Walk::Guard, found}
    end
    if (elvis = before.index("?:")) && head[(elvis + 2)..].matches?(/\A\s*return\b/)
      return {Walk::Guard, found}
    end
    head.matches?(/\A(?:return|throw)\b/) ? {Walk::Guard, found} : {Walk::Refused, found}
  end

  # The refusing text of a statement: a 401/403 status or auth exception, a
  # status constant handed to a call, a call to a method of the class that
  # refuses, or a call named for the refusal that the class does not declare.
  private def refusal_in(statement : String, reading : FilterReading) : String?
    if found = statement.match(INTERCEPTOR_REJECTION_RE) || statement.match(REFUSAL_STATUS_CONSTANT)
      return found[0]
    end
    return unless call = statement.match(STATEMENT_CALL)
    name = call[1]
    return reading.helpers[name] if reading.helpers.has_key?(name)
    name if !reading.declared.includes?(name) && name.matches?(/Unauthori[sz]ed|Forbidden|AccessDenied|Authentication\w*Exception/i)
  end

  # Branch by branch: a branch the caller takes decides; one on paths or
  # settings that hands the request on narrows the filter to the rest.
  private def walk_branches(branches : Array({String?, String}), reading : FilterReading) : {Walk, String?}
    walked = branches.map { |cond, body| {cond.try { |text| evaluate_condition(text, reading) } || CondVerdict.new(:true), walk_block(unwrap_block(body), reading)} }
    walked.each_with_index do |(verdict, result), index|
      if result[0].through?
        return result if verdict.kind == :true
        next if verdict.kind == :false
        # Taken or not, nothing else happens there, unless a later branch acts.
        return {Walk::Unknown, nil} if walked[(index + 1)..].any? { |_, later| !later[0].through? }
        next
      end
      case verdict.kind
      when :true  then return result
      when :false then next
      when :limited
        if result[0].pass?
          verdict.tests.each do |paths, negated|
            negated ? reading.required << paths : reading.excluded.concat(paths)
          end
          reading.settings.concat(verdict.settings)
          next
        end
        if (result[0].guard? || result[0].refused?) && verdict.tests.empty?
          reading.settings.concat(verdict.settings.map { |setting| "!(#{setting})" })
          return result
        end
        return {Walk::Unknown, nil}
      else
        return {Walk::Unknown, nil}
      end
    end
    {Walk::Through, nil}
  end

  # `try { .. } catch { .. }`: a try block that hands the request on decides
  # alone (a catch then answers for the handler, after it ran). One that
  # passes the credential to a call, with a catch that refuses, refuses a
  # missing credential.
  private def walk_try(text : String, reading : FilterReading) : {Walk, String?}
    masked = mask_literals(text)
    return {Walk::Unknown, nil} unless open = masked.index('{')
    return {Walk::Unknown, nil} unless close = Noir::JSLiteralScanner.find_matching_brace(masked, open)
    block = text[(open + 1)...close]
    result = walk_block(block, reading)
    return result unless result[0].through?
    return result if mask_literals(block).includes?("doFilter")

    hands_credential = block.matches?(CREDENTIAL_EXPRESSION) || block.scan(IDENTIFIER).any? { |ident| reading.credential.includes?(ident[0]) }
    rest = masked[(close + 1)..]
    offset = close + 1
    while found = rest.match(/\A\s*catch\s*\(/)
      paren = offset + found.end(0) - 1
      break unless paren_close = Noir::JSLiteralScanner.find_matching_paren(masked, paren)
      break unless (catch_open = masked.index('{', paren_close)) && (catch_close = Noir::JSLiteralScanner.find_matching_brace(masked, catch_open))
      caught = walk_block(text[(catch_open + 1)...catch_close], reading)
      # ponytail: assumes the call throws for a missing credential, as a validator does.
      return caught if hands_credential && (caught[0].guard? || caught[0].refused?)
      offset = catch_close + 1
      rest = masked[offset..]
    end
    {Walk::Through, nil}
  end

  # `{cond, body}` of each branch of an if / else-if / else chain (nil cond: `else`).
  private def if_branches(text : String) : Array({String?, String})
    masked = mask_literals(text)
    branches = [] of {String?, String}
    pos = 0
    loop do
      return branches unless (paren = masked.index('(', pos)) && (close = Noir::JSLiteralScanner.find_matching_paren(masked, paren))
      stop = branch_body_end(masked, close + 1)
      branches << {text[(paren + 1)...close], text[(close + 1)...stop].strip}
      return branches unless follow = masked[stop..].match(/\A\s*else\b\s*/)
      pos = stop + follow.end(0)
      next if masked[pos..].matches?(/\Aif\s*\(/)
      branches << {nil, text[pos...branch_body_end(masked, pos)].strip}
      return branches
    end
  end

  # Kotlin `when { cond -> .. }` / `when (subject) { null -> .. }` as
  # branches; nil for a subject noir cannot read (`when (val t = ..)`).
  private def when_branches(text : String) : Array({String?, String})?
    masked = mask_literals(text)
    subject = nil
    head = masked.match!(/\Awhen\s*/).end(0)
    if masked[head]? == '('
      return unless close = Noir::JSLiteralScanner.find_matching_paren(masked, head)
      subject = text[(head + 1)...close].strip
      return if subject.matches?(/\A(?:val|var)\b/)
      head = close + 1
    end
    return unless (open = masked.index('{', head)) && (close = Noir::JSLiteralScanner.find_matching_brace(masked, open))
    Noir::TopLevelSplit.split(text[(open + 1)...close], '\n', Noir::TopLevelSplit::Rules.new).compact_map do |entry|
      parts = Noir::TopLevelSplit.split(entry, "->", Noir::TopLevelSplit::Rules.new)
      next if parts.size < 2
      cond = parts[0].strip
      body = parts[1..].join("->")
      if cond == "else"
        {nil, body}
      elsif subject
        {"#{subject} == #{cond}", body}
      else
        {cond, body}
      end
    end
  end

  private def unwrap_block(body : String) : String
    body = body.strip
    return body unless body.starts_with?('{') && Noir::JSLiteralScanner.find_matching_brace(mask_literals(body), 0) == body.size - 1
    body[1...-1]
  end

  # Yields `{start, stop}` of each top-level statement of masked `code`.
  private def each_statement(code : String, &)
    pos = 0
    while pos < code.size
      if code[pos].whitespace? || code[pos] == ';'
        pos += 1
        next
      end
      stop = statement_end(code, pos)
      stop = pos + 1 if stop <= pos
      yield pos, stop
      pos = stop
    end
  end

  private def statement_end(code : String, pos : Int32) : Int32
    rest = code[pos..]
    if rest.matches?(/\Aif\s*\(/)
      loop do
        return code.size unless (paren = code.index('(', pos)) && (close = Noir::JSLiteralScanner.find_matching_paren(code, paren))
        stop = branch_body_end(code, close + 1)
        return stop unless follow = code[stop..].match(/\A\s*else\b\s*/)
        pos = stop + follow.end(0)
        return branch_body_end(code, pos) unless code[pos..].matches?(/\Aif\s*\(/)
      end
    elsif rest.matches?(/\Atry\b/)
      stop = branch_body_end(code, pos + 3)
      while found = code[stop..].match(/\A\s*(?:catch\s*\(|finally\b)/)
        at = stop + found.end(0)
        if found[0].includes?('(')
          return code.size unless close = Noir::JSLiteralScanner.find_matching_paren(code, at - 1)
          at = close + 1
        end
        stop = branch_body_end(code, at)
      end
      stop
    elsif found = rest.match(/\A(?:for|while|switch|synchronized|when)\s*(?=\()/)
      return code.size unless close = Noir::JSLiteralScanner.find_matching_paren(code, pos + found.end(0))
      branch_body_end(code, close + 1)
    elsif found = rest.match(/\Awhen\s*(?=\{)/)
      branch_body_end(code, pos + found.end(0))
    else
      simple_statement_end(code, pos)
    end
  end

  # End of a block `{ .. }` or single statement starting after `pos`.
  private def branch_body_end(code : String, pos : Int32) : Int32
    while pos < code.size && code[pos].whitespace?
      pos += 1
    end
    return code.size if pos >= code.size
    if code[pos] == '{'
      (Noir::JSLiteralScanner.find_matching_brace(code, pos) || code.size - 1) + 1
    else
      statement_end(code, pos)
    end
  end

  # End of a simple statement: `;`, a newline that does not continue the
  # expression (Kotlin), an `else`, or the enclosing block's close.
  private def simple_statement_end(code : String, pos : Int32) : Int32
    depth = 0
    index = pos
    while index < code.size
      char = code[index]
      case char
      when '(', '[', '{' then depth += 1
      when ')', ']', '}'
        return index if depth == 0
        depth -= 1
      when ';'
        return index + 1 if depth == 0
      when '\n'
        if depth == 0
          before = code[pos...index].rstrip[-1]?
          after = code[index..].lstrip
          return index unless before.nil? || "=+-*/%&|,(.:?<>!".includes?(before) || after.matches?(/\A(?:\.|\?[.:]|&&|\|\||:|\+)/)
        end
      when 'e'
        return index if depth == 0 && index > pos && code[index - 1].whitespace? && code[index..].matches?(/\Aelse\b/)
      end
      index += 1
    end
    code.size
  end

  # `text` with the inside of every string and char literal blanked, same length.
  private def mask_literals(text : String) : String
    text.gsub(STRING_LITERAL) { |literal| "#{literal[0]}#{"x" * (literal.size - 2)}#{literal[-1]}" }
  end

  # What `cond` is for a caller without a credential. Each `||` disjunct
  # is a config switch that reads only fields (limited to a setting), a
  # path test (limited to paths), or a conjunction of credential tests
  # (`key == null`: true; `key != null && !valid(key)`: false). Anything
  # else, a method or path conjunct in particular, is unknown.
  private def evaluate_condition(cond : String, reading : FilterReading) : CondVerdict
    tests = [] of {Array(PathTest), Bool}
    settings = [] of String
    unknown = false
    Noir::TopLevelSplit.split(cond, "||", Noir::TopLevelSplit::Rules.new).each do |part|
      disjunct = strip_parens(part)
      next if disjunct == "false" || options_test?(disjunct)
      return CondVerdict.new(:true) if disjunct == "true"
      if identifiers(disjunct).any? { |ident| reading.tainted.includes?(ident) } && (found = path_tests(disjunct, reading.body))
        tests.concat(found)
      elsif config_switch?(disjunct, reading)
        settings << disjunct
      else
        conjuncts = Noir::TopLevelSplit.split(disjunct, "&&", Noir::TopLevelSplit::Rules.new).map { |atom| evaluate_atom(atom, reading) }
        if conjuncts.includes?(:false)
          next
        elsif conjuncts.all?(:true)
          return CondVerdict.new(:true)
        else
          unknown = true
        end
      end
    end
    return CondVerdict.new(:unknown) if unknown
    return CondVerdict.new(:false) if tests.empty? && settings.empty?
    CondVerdict.new(:limited, tests, settings)
  end

  # One credential test: true when a missing credential satisfies it.
  private def evaluate_atom(atom : String, reading : FilterReading) : Symbol
    atom = strip_parens(atom)
    negated = atom.starts_with?('!') && !atom.starts_with?("!=")
    atom = atom[1..].strip if negated
    value = if atom.starts_with?('(') && Noir::JSLiteralScanner.find_matching_paren(mask_literals(atom), 0) == atom.size - 1
              case evaluate_condition(atom[1...-1], reading).kind
              when :true  then :true
              when :false then :false
              else             :unknown
              end
            else
              credential_test(atom, reading)
            end
    return value if value == :unknown || !negated
    value == :true ? :false : :true
  end

  # What an inline `access(<lambda>)` decides for a signed-out caller:
  # `:open` (admits only anonymous callers: `!isAuthenticated`, `isAnonymous`),
  # `:guard` (needs a signed-in one: `isAuthenticated`, `!isAnonymous`, a type
  # test refusing on empty), nil when it is not a lambda or not readable.
  private def access_lambda(arg : String) : Symbol?
    return unless arg.matches?(/\A\s*(?:\([^()]*\)|[\w$]+)\s*->/)
    return :open if arg.matches?(ACCESS_NEG_AUTH)
    return :guard if arg.matches?(ACCESS_NEG_ANON)
    return :open if arg.matches?(ACCESS_ANON)
    return :guard if arg.matches?(ACCESS_AUTH)
    :guard if arg.matches?(ACCESS_TYPE_TEST) && arg.matches?(/switchIfEmpty[^;]*false/m)
  end

  # A request attribute is set on the server side (an earlier filter marking
  # the request authenticated), never by the caller: unset for a caller
  # without a credential.
  ATTRIBUTE_EQUALS = /\A[\w$.]+\s*\.\s*equals\s*\(\s*([\w$]+)\s*\.\s*getAttribute\s*\([^()]*\)\s*\)\z/
  ATTRIBUTE_NULL   = /\A([\w$]+)\s*\.\s*getAttribute\s*\([^()]*\)\s*(!=|==)\s*null\z/

  private def credential_test(atom : String, reading : FilterReading) : Symbol
    if (found = atom.match(ATTRIBUTE_EQUALS) || atom.match(ATTRIBUTE_NULL)) && reading.tainted.includes?(found[1])
      return found[2]? == "==" ? :true : :false
    end
    return :unknown unless atom.matches?(CREDENTIAL_EXPRESSION) || identifiers(atom).any? { |ident| reading.credential.includes?(ident) }
    return :unknown if identifiers(atom).any? { |ident| reading.murky.includes?(ident) }
    rest = atom.gsub(CREDENTIAL_EXPRESSION, " ")
    return :unknown if identifiers(rest).any? { |ident| reading.tainted.includes?(ident) && !reading.credential.includes?(ident) }
    masked = mask_literals(atom)
    if masked.matches?(/(?<![!=])===?\s*null\b|\bnull\s*===?(?!=)/)
      :true
    elsif masked.matches?(/!==?\s*null\b|\bnull\s*!==?/)
      :false
    elsif masked.matches?(/\b(?:isEmpty|isBlank|isNullOrEmpty|isNullOrBlank)\s*\(/)
      :true
    elsif masked.matches?(/!=/) || masked.matches?(/\s!in\s/)
      :true
    elsif masked.matches?(/[<>]/)
      :unknown
    else
      # `key == expected`, `key in keys`, `valid(key)`, `hasText(key)`,
      # `key.startsWith("Bearer ")`, a validated flag: a missing credential fails it.
      :false
    end
  end

  private def options_test?(disjunct : String) : Bool
    disjunct.matches?(/"OPTIONS"|HttpMethod\.OPTIONS\b/) && disjunct.matches?(/\bmethod\b|getMethod\s*\(/) && !disjunct.includes?("&&")
  end

  # A condition that reads only fields and properties (`!enabled`,
  # `!props.isEnabled()`), nothing request-derived.
  # Each value read is a configuration field (`enabled` under `@Value`,
  # `authConfig.isEnabled()` on a `*Config` field), or a no-argument
  # method of the class that returns only such a read. A no-argument call
  # on anything else (`isPublic()`, `SecurityBypass.isAnonymousAllowed()`)
  # can read the request through a ThreadLocal.
  private def config_switch?(disjunct : String, reading : FilterReading, depth = 0) : Bool
    masked = mask_literals(disjunct)
    return false if masked.matches?(REQUEST_HOLDER) || masked.matches?(/[\w$]\s*\(\s*[^)\s]|->|\{/)
    roots = masked.scan(/(?<![\w$.])(?:this\s*\.\s*)?([A-Za-z_$][\w$]*)(\s*\()?/).reject { |root| {"true", "false", "null", "this"}.includes?(root[1]) }
    return false if roots.empty?
    roots.all? do |root|
      name = root[1]
      next false if reading.tainted.includes?(name)
      if root[2]?
        depth == 0 && (value = reading.body.match(/\b(?:boolean|Boolean|fun)\s+#{Regex.escape(name)}\s*\(\s*\)\s*(?::\s*Boolean\s*)?(?:\{\s*return\s+([^;{}]+?)\s*;?\s*\}|=\s*([^\n;{}]+))/)) &&
          config_switch?(value[1]? || value[2], reading, depth + 1)
      else
        config_field?(name, reading.body)
      end
    end
  end

  private def config_field?(name : String, body : String) : Bool
    escaped = Regex.escape(name)
    return false unless found = body.match(/(@Value\s*\([^)]*\)\s*)?(?:(?:private|protected|public|internal|final|static|lateinit|override)\s+)*(?:(?:val|var)\s+#{escaped}\s*:\s*([\w.<>?]+)|([\w.<>]+)\s+#{escaped}\s*[;=])/)
    !found[1]?.nil? || (found[2]? || found[3]).matches?(CONFIG_FIELD_TYPE)
  end

  private def identifiers(text : String) : Array(String)
    text.gsub(STRING_LITERAL, "\"\"").scan(IDENTIFIER).map(&.[0])
  end

  private def strip_parens(text : String) : String
    text = text.strip
    while text.starts_with?('(') && Noir::JSLiteralScanner.find_matching_paren(mask_literals(text), 0) == text.size - 1
      text = text[1...-1].strip
    end
    text
  end

  # Methods of a filter class whose body refuses the request, with the
  # refusing text, and every method name the class declares.
  private def refusing_helpers(body : String) : {Hash(String, String), Set(String)}
    helpers = Hash(String, String).new
    declared = Set(String).new
    body.scan(/(?:\bfun|\bvoid|\b[\w$<>\[\]]+)\s+([a-z_$][\w$]*)\s*\(/) do |decl|
      name = decl[1]
      next unless params = paren_inner(body, decl.byte_end(0) - 1)
      rest = params[1]
      next unless open = body.byte_index('{', rest)
      next unless body.byte_slice(rest, open - rest).matches?(/\A[^;=]*\z/)
      declared << name
      next if name.starts_with?("doFilter") || name == "shouldNotFilter"
      next unless close = Noir::JSLiteralScanner.find_matching_brace_at_byte(body, open)
      if found = body.byte_slice(open, close - open + 1).match(INTERCEPTOR_REJECTION_RE)
        helpers[name] = found[0]
      end
    end
    {helpers, declared}
  end

  # The request parameter of a filter method (the first one) and the locals
  # derived from it (`String path = request.getRequestURI()`), then the
  # subset of those holding the caller's credential (`token = request.getHeader("Authorization")`).
  private def request_names(params : String, body : String) : {Set(String), Set(String), Set(String)}
    first = Noir::TopLevelSplit.split(params, ',', Noir::TopLevelSplit::Rules.new).first? || ""
    name = first.includes?(':') ? first.split(':').first : first.split(/\s+/).last
    tainted = Set{name.strip}
    credential = Set(String).new
    murky = Set(String).new
    masked = mask_literals(body)
    assignments = [] of {String, String}
    masked.scan(/(?<![\w$.])([a-z_$][\w$]*)\s*(?::\s*[\w$.<>?]+\s*)?=(?![=>])/) do |assign|
      assignments << {assign[1], body[assign.end(0)...simple_statement_end(masked, assign.end(0))]}
    end
    2.times do
      assignments.each do |local, value|
        idents = identifiers(value)
        tainted << local if idents.any? { |ident| tainted.includes?(ident) } || value.matches?(REQUEST_HOLDER)
        unless value.matches?(FILTER_CREDENTIAL_READ) || idents.any? { |ident| credential.includes?(ident) }
          # A credential local given a value of another kind (`token = "guest"`).
          murky << local if credential.includes?(local)
          next
        end
        credential << local
        murky << local if mask_literals(value).matches?(MURKY_VALUE) || idents.any? { |ident| murky.includes?(ident) }
      end
    end
    {tainted, credential, murky}
  end

  # `shouldNotFilter` returns true for the requests the filter skips: read
  # its expression body, or the `if (c) return true` / `return e` of its
  # block. Each condition must be a path test or a config switch.
  private def read_should_not_filter(body : String, decl : Regex::MatchData, filter_reading : FilterReading) : Bool
    return false unless params = paren_inner(body, decl.byte_end(0) - 1)
    rest = body.byte_slice(params[1])
    conditions = [] of String
    block = ""
    if expr = rest.match(/\A\s*(?::\s*Boolean\s*)?=\s*(.+?)(?=\n\s*(?:override\b|fun\b|public\b|protected\b|private\b|@|\})|\z)/m)
      conditions << expr[1]
      block = expr[1]
    else
      return false unless (open = rest.index('{')) && (close = Noir::JSLiteralScanner.find_matching_brace(rest, open))
      block = rest[(open + 1)...close]
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
    end
    tainted, credential, murky = request_names(params[0], block)
    reading = FilterReading.new(tainted, credential, murky, body, filter_reading.helpers, filter_reading.declared)
    conditions.each do |cond|
      verdict = evaluate_condition(cond, reading)
      next if verdict.kind == :false
      return false unless verdict.kind == :limited
      verdict.tests.each { |paths, negated| negated ? filter_reading.required << paths : filter_reading.excluded.concat(paths) }
      filter_reading.settings.concat(verdict.settings)
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
    # A conjunction of tests is read only when every one is negated (the filter runs on any of them).
    return if tests.size > 1 && !tests.all?(&.[1])
    tests.size > 1 ? [{tests.flat_map(&.[0]), true}] : tests
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
      # The annotations of the `@Bean` method holding it.
      lead_start = [found.byte_begin(0) - 600, 0].max
      lead = clean.byte_slice(lead_start, found.byte_begin(0) - lead_start).scrub
      bean_lead = (at = lead.rindex("@Bean")) ? lead[at..] : ""

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
        generic_text = (lead[-300..]? || lead) + found[0]
        generic_text.scan(/FilterRegistrationBean\s*<\s*([A-Z][\w$]*)/) { |generic| names = [generic[1]] }
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

      enabled = chunk.match(/\bsetEnabled\s*\(\s*([^()]*?)\s*\)|\b(?:isEnabled|enabled)\s*=\s*([^;\n]+)/)
      enabled_call = enabled.try(&.[0].strip)
      enabled_value = enabled.try { |found_enabled| (found_enabled[1]? || found_enabled[2]).strip }
      settings = bean_lead.scan(CONDITIONAL_REGISTRATION).map { |conditional| "it is registered only under `#{conditional[0]}`" }
      settings << "its registration is enabled by `#{enabled_call}`" if enabled_value && enabled_value != "true" && enabled_value != "false"

      @filter_registrations << ServletFilterRegistration.new(
        names: names.uniq,
        file_path: file,
        line: clean.byte_slice(0, found.byte_begin(0)).count('\n') + 1,
        patterns: readable ? patterns : nil,
        enabled: enabled_value != "false",
        module_dir: module_dir,
        settings: settings
      )
    end
  end

  # The packages `module_dir` component-scans and the classes it imports.
  private def scan_component_packages(content : String, module_dir : String)
    clean = Noir::CComments.strip(content)
    packages = @scan_packages[module_dir] ||= [] of String
    if clean.includes?("@SpringBootApplication") && (package = clean.match(/^\s*package\s+([\w.]+)/m))
      packages << package[1]
    end
    clean.scan(/@(?:SpringBootApplication|ComponentScan)\s*\(/) do |found|
      next unless args = paren_inner(clean, found.byte_end(0) - 1)
      # `exclude`, `excludeName` and `excludeFilters` name what is NOT scanned.
      excluded, kept = Noir::TopLevelSplit.split(args[0], ',', Noir::TopLevelSplit::Rules.new)
        .partition(&.matches?(/\A\s*exclude\w*\s*=/))
      excluded.each do |arg|
        arg.scan(/\b([A-Z][\w$]*)(?:::|\.)class\b/) { |klass| (@scan_excludes[module_dir] ||= [] of String) << klass[1] }
      end
      included = kept.join(',')
      included.scan(/"([\w.]+)"/) { |literal| packages << literal[1] }
      included.scan(/\b([A-Z][\w$]*)(?:::|\.)class\b/) { |klass| (@scan_imports[module_dir] ||= [] of String) << klass[1] }
    end
    clean.scan(/@Import\s*\(/) do |found|
      next unless args = paren_inner(clean, found.byte_end(0) - 1)
      args[0].scan(/\b([A-Z][\w$]*)(?:::|\.)class\b/) { |klass| (@scan_imports[module_dir] ||= [] of String) << klass[1] }
    end
  end

  # Types returned by `@Bean` methods: Spring Boot maps a filter bean to
  # every request unless a `FilterRegistrationBean` registers it. A bean
  # method that returns null registers nothing.
  private def scan_bean_types(content : String, module_dir : String?)
    clean = Noir::CComments.strip(content)
    clean.scan(/@Bean\b/) do |found|
      after = clean.byte_slice(found.byte_end(0), [clean.bytesize - found.byte_end(0), 400].min).scrub
      next if after.matches?(/\A[^{=]*\{\s*return\s+null\s*;?\s*\}/)
      if java = after.match(/\A(?:\s*@[\w.]+(?:\([^)]*\))?)*\s*(?:(?:public|protected|private|static|final)\s+)*([A-Z][\w$]*)(?:\s*<[^>]*>)?\s+[a-z_$][\w$]*\s*\(/)
        @bean_types << {module_dir, java[1]}
      elsif kotlin = after.match(/\A(?:\s*@[\w.]+(?:\([^)]*\))?)*\s*(?:\w+\s+)*fun\s+[\w$]+\s*\([^)]*\)\s*(?::\s*([A-Z][\w$]*)|=\s*([A-Z][\w$]*)\s*\()/)
        @bean_types << {module_dir, kotlin[1]? || kotlin[2]}
      end
    end
  end

  # "Protected by Servlet filter X on PATTERN (refuses with N)" when a
  # refusing filter on the classpath is mapped to the endpoint URL. The URL
  # is matched below the app's `server.servlet.context-path`.
  private def servlet_filter_decision(endpoint : Endpoint, classpath : Set(String)?, app : String?) : Tuple(String, String, Int32)?
    url = normalize_security_path(endpoint.url)
    if app
      return unless context = servlet_context_path(app)
      unless context.empty?
        return unless url == context || url.starts_with?("#{context}/")
        url = normalize_security_path(url[context.size..])
      end
    end
    applies = ->(owner : String?) { owner.nil? || classpath.nil? || classpath.includes?(owner) }

    @servlet_filters.each do |filter|
      next unless (refusal = filter.refusal) && applies.call(filter.module_dir)
      next unless filter.required.all? { |tests| tests.any? { |test| path_test_matches?(url, test) } }
      next if filter.excluded.any? { |test| path_test_matches?(url, test) }

      # A registration names its filter by type: the one in its own module when there is one.
      registrations = @filter_registrations.select do |reg|
        reg.names.includes?(filter.name) && applies.call(reg.module_dir) &&
          (reg.module_dir == filter.module_dir || @servlet_filters.none? { |other| other.name == filter.name && other.module_dir == reg.module_dir })
      end
      mappings = [] of {String, String, Int32, Array(String)}
      registrations.each do |reg|
        next unless reg.enabled
        reg.patterns.try &.each { |pattern| mappings << {pattern, reg.file_path, reg.line, reg.settings} }
      end
      # Spring Boot maps a filter bean it finds no registration for to `/*`.
      # ponytail: a `@Component @WebFilter` class is read as its `@WebFilter`
      # patterns, and a `@Component` that is also registered as its
      # registration's, though Boot registers that bean for `/*` as well.
      bean = (filter.component && scanned_by?(filter, app)) || @bean_types.any? { |owner, type| type == filter.name && applies.call(owner) }
      if registrations.empty? && filter.web_filter_patterns.nil? && bean
        mappings << {"/*", filter.file_path, filter.line, [] of String}
      end
      if (patterns = filter.web_filter_patterns) && (@boot_apps.empty? || @servlet_component_scans.any? { |owner| applies.call(owner) }) && scanned_by?(filter, app)
        patterns.each { |pattern| mappings << {pattern, filter.file_path, filter.line, [] of String} }
      end

      next unless mapping = mappings.find { |pattern, _, _, _| servlet_pattern_matches?(url, pattern) }
      scope = mapping[0]
      if scope == "/*" && (inside = filter.required.flatten.find { |test| path_test_matches?(url, test) })
        scope = inside[:exact] ? inside[:path] : "#{inside[:path]}*"
      end
      settings = filter.settings + mapping[3]
      note = settings.empty? ? "" : "; a setting can lift it: #{settings.uniq.join("; ")}"
      return {"Protected by Servlet filter #{filter.name} on #{scope} (refuses with #{refusal})#{note}", mapping[1], mapping[2]}
    end
    nil
  end

  @context_paths = Hash(String, String?).new

  # Whether `app` component-scans `filter`: a filter of the app's own
  # module, or one in another module under a package the app's
  # `@SpringBootApplication` / `scanBasePackages` / `@ComponentScan` names
  # or that it `@Import`s.
  private def scanned_by?(filter : ServletFilterDef, app : String?) : Bool
    return true if app.nil?
    return false if @scan_excludes[app]?.try(&.includes?(filter.name))
    return true if filter.module_dir == app
    return true if @scan_imports[app]?.try(&.includes?(filter.name))
    @scan_packages[app]?.try(&.any? { |package| filter.package_name == package || filter.package_name.starts_with?("#{package}.") }) || false
  end

  # `server.servlet.context-path` of `app` ("" unset), nil when a profile,
  # an import or a placeholder can set it.
  private def servlet_context_path(app : String) : String?
    @context_paths.put_if_absent(app) do
      values, note = module_config_list(app, "server.servlet.context-path")
      note ? nil : (values.try(&.first?).try { |value| normalize_security_path(value).rchop('/') } || "")
    end
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

  private def scan_security_chain(block : String, strings : Hash(String, String), arrays : Hash(String, Array(String)), module_dir : String?, java_source : String?, file_path : String, block_start_line : Int32)
    scope = chain_scope(block, strings, arrays)
    builders = servlet_path_builders(block, strings, arrays)
    rules = [] of SecurityRule
    # A rule whose matcher noir cannot read (`EndpointRequest.toAnyEndpoint()`)
    # may be the one that decides a request no read rule matches.
    unread_matcher = false
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
      # An inline `access((authentication, context) -> ..)` that admits only
      # signed-out callers (`!isAuthenticated`) is a public page, not a guard.
      access_verdict = nil
      if auth_type == "access" && (paren = close + rule.byte_end(0)) < block.bytesize && block.to_unsafe[paren] == '('.ord
        if access_close = Noir::JSLiteralScanner.find_matching_paren_at_byte(block, paren)
          access_verdict = access_lambda(block.byte_slice(paren + 1, access_close - paren - 1))
        end
      end
      if access_verdict == :open
        protected_rule = false
        is_anonymous = true
      end
      matcher_method = request_matcher_method(args)
      config_keys = [] of String
      in_scope = loops_enclosing(loops, open)
      rule_line = block_start_line + block[0, match.begin(1)].count('\n')
      patterns = matcher_patterns(args, strings, arrays, loops: in_scope, config_keys: config_keys, java_source: java_source, builders: builders).uniq
      unread_matcher ||= patterns.empty? && config_keys.empty?
      patterns.each do |url_pattern|
        description =
          if protected_rule
            "Protected by Spring Security #{auth_type} via #{match[1]}(\"#{url_pattern}\")#{ACCESS_NOTE if auth_type == "access" && access_verdict.nil?}"
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

    form_rules = scan_form_login_rules(block, strings, file_path, block_start_line, module_dir)

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
          rules << {pattern: "/**", method: nil, description: "#{verb} via authorize(#{match[3]})", protected_rule: protected_rule, module: module_dir, config_key: nil, path: file_path, line: line_num}
        end
      end
    end

    if any_request_covered
      block.scan(ANY_REQUEST_AUTH) do |match|
        auth_type = match[1]
        len = Math.min(120, block.bytesize - match.byte_begin(0))
        slice = block.byte_slice(match.byte_begin(0), len)
        is_anonymous = auth_type == "anonymous" ||
                       (auth_type == "hasRole" && slice.matches?(/\.\s*any(?:Request|Exchange)\s*\(\s*\)\s*\.\s*hasRole\s*\(\s*["'](?:ROLE_)?ANONYMOUS["']\s*\)/)) ||
                       (auth_type == "hasAuthority" && slice.matches?(/\.\s*any(?:Request|Exchange)\s*\(\s*\)\s*\.\s*hasAuthority\s*\(\s*["'](?:ROLE_)?ANONYMOUS["']\s*\)/))
        protected_rule = auth_type != "permitAll" && !is_anonymous
        rule_line = block_start_line + block[0, match.begin(1)].count('\n')
        any_call = slice.includes?("anyExchange") ? "anyExchange()" : "anyRequest()"
        description =
          if protected_rule
            "Protected by Spring Security #{auth_type} via #{any_call}"
          elsif is_anonymous
            "Public by Spring Security anonymous via #{any_call}"
          else
            "Public by Spring Security permitAll via #{any_call}"
          end
        rules << {pattern: "/**", method: nil, description: description, protected_rule: protected_rule, module: module_dir, config_key: nil, path: file_path, line: rule_line}
      end
    end

    # What the read rules leave to the chain: rules noir cannot read, or a
    # request no rule matches, which `authorizeHttpRequests` /
    # `authorizeExchange` deny (legacy `authorizeRequests` lets it through).
    # A `Customizer<HttpSecurity>` bean only adds rules to a chain declared
    # elsewhere, which decides the rest itself.
    if any_request_covered && !unread_matcher && (dsl = block.match(AUTHORIZATION_DSL)) && rules.none? { |rule| rule[:pattern] == "/**" && rule[:method].nil? }
      description = if rules.empty?
                      "Protected by Spring Security, configured by the authorization rules of the chain in #{File.basename(file_path)}, which noir does not read"
                    elsif dsl[0] != "authorizeRequests" && block.matches?(CHAIN_DECLARATION)
                      "Protected by Spring Security: #{dsl[0]} denies a request no rule matches"
                    end
      rules << {pattern: "/**", method: nil, description: description, protected_rule: true, module: module_dir, config_key: nil, path: file_path, line: block_start_line + block[0, dsl.begin(0)].count('\n')} if description
    end
    rules.concat(form_rules)

    # A chain declared under `@Profile("auth")` / `@ConditionalOn…` guards
    # only while that holds: say so instead of reporting an unconditional guard.
    unless (conditions = chain_conditions(block, java_source, block_start_line)).empty?
      note = "; a setting can lift it: #{conditions.join("; ")}"
      rules = rules.map do |rule|
        next rule unless rule[:protected_rule]
        {pattern: rule[:pattern], method: rule[:method], description: rule[:description] + note, protected_rule: true, module: rule[:module], config_key: rule[:config_key], path: rule[:path], line: rule[:line]}
      end
    end

    if scope && !scope.empty?
      @scoped_chains << {scope: scope, order: chain_order(block), rules: rules, module: module_dir}
    else
      @security_rules.concat(rules)
    end
  end

  CLASS_DECLARATION = /\b(?:class|object)\s+[A-Za-z_$][\w$]*[^{;=]*\{/
  DECLARATION_START = /[;}][ \t]*\r?\n/

  # The `@Profile` / `@ConditionalOn…` conditions the chain `block` is
  # registered under: the annotations leading its own declaration and those
  # of every class enclosing it (`java_source` is the whole file; nil, Kotlin,
  # reads the first only).
  private def chain_conditions(block : String, java_source : String?, block_start_line : Int32) : Array(String)
    leads = [] of String
    if boundary = block.match(CHAIN_BOUNDARY)
      leads << declaration_lead(block.byte_slice(0, boundary.byte_begin(0)))
    end
    if (code = java_source) && (code.includes?("@Profile") || code.includes?("@ConditionalOn"))
      start = 0
      (block_start_line - 1).times { start = (code.byte_index('\n'.ord.to_u8, start) || break) + 1 }
      code.scan(CLASS_DECLARATION) do |decl|
        break if decl.byte_begin(0) >= start
        next unless (close = Noir::JSLiteralScanner.find_matching_brace_at_byte(code, decl.byte_end(0) - 1)) && close >= start
        leads << declaration_lead(code.byte_slice(0, decl.byte_begin(0)))
      end
    end
    leads.flat_map(&.scan(CONDITIONAL_REGISTRATION).map { |found| "it is registered only under `#{found[0]}`" }).uniq!
  end

  # The annotations and modifiers right before a declaration: what follows
  # the previous statement or block end in `before`.
  private def declaration_lead(before : String) : String
    tail = before.size > 600 ? before[-600..] : before
    tail[((tail.rindex(DECLARATION_START).try { |idx| idx + 1 }) || 0)..]
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

  LOOP_HEADER      = /\A\s*(?:final\s+)?[\w$.<>\[\]]+\s+([a-z_$][\w$]*)\s*:\s*(.+?)\s*\z/m
  FOR_EACH_BINDING = /([\w$.]+\s*\(\s*\)(?:\s*\.\s*[\w$]+\s*\(\s*\))*)\s*\.\s*forEach\s*(\()\s*\(?\s*(?:[\w$]+\s+)?([a-z_$][\w$]*)\s*\)?\s*->/

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
  private def check_security_config_rules(endpoint : Endpoint) : Tuple(String, String?, Int32?)?
    serving : String? = nil
    decision = per_serving_classpath(endpoint, false) do |classpath, app|
      security_decision(endpoint, app, classpath).tap { |found| serving = app if found }
    end
    return unless decision
    # A Boot app that bundles other modules (an assembly) is not what runs
    # the module on its own: when the module's own app declares no chain,
    # the guard holds only inside the bundling app.
    own = endpoint_modules(endpoint).first?
    if (app = serving) && own && own != app && @boot_apps.includes?(own) && module_classpath(own) && security_decision(endpoint, own, module_classpath(own).try(&.[0])).nil?
      decision = {"#{decision[0]}; #{File.basename(own)} run on its own has no such chain, only #{File.basename(app)}, which bundles it", decision[1], decision[2]}
    end
    decision
  end

  # `config_dir` holds the configuration lists are read from; `classpath`
  # (nil: unknown, every chain applies) the modules whose chains apply.
  private def security_decision(endpoint : Endpoint, config_dir : String?, classpath : Set(String)?) : Tuple(String, String?, Int32?)?
    url = endpoint.url
    applies = ->(owner : String?) { owner.nil? || classpath.nil? || classpath.includes?(owner) }
    # A security configuration or switch outside any build unit (an example
    # under `docs/`) reaches only endpoints whose classpath is unknown.
    reaches = ->(owner : String?) { owner ? applies.call(owner) : classpath.nil? }
    if config_dir && classpath && @chain_modules.none? { |owner| applies.call(owner) } && @unread_configs.none? { |config| reaches.call(config[:module]) } &&
       module_classpath(config_dir).try(&.[1])
      # The app declares no chain, yet Spring Security is on its classpath
      # and switched on: its default chain authenticates every request.
      if @security_enabled.any? { |owner| reaches.call(owner) }
        return {"Protected by Spring Security default chain (@EnableWebSecurity, no SecurityFilterChain on the app's classpath)", nil, nil}
      elsif @boot_apps.empty? || @boot_apps.includes?(config_dir)
        return {"Protected by Spring Boot default security (Spring Security on the app's classpath, no SecurityFilterChain in it)", nil, nil}
      end
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
    if best.nil? && (unread = @unread_configs.find { |config| reaches.call(config[:module]) })
      # No rule noir reads decides the request, but a configuration it does
      # not read can.
      return {"Protected by Spring Security, configured by #{unread[:what]}, which noir does not read#{note}", unread[:path], unread[:line]}
    end
    return unless best && best[:protected_rule]

    {"#{best[:description]}#{note}", best[:path], best[:line]}
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
    return if endpoint.internal
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
    per_serving_classpath(endpoint, true) { |classpath, _| interceptor_decision(endpoint, classpath) }
  end

  private def check_servlet_filter_rules(endpoint : Endpoint) : Tuple(String, String, Int32)?
    return if @servlet_filters.none?(&.refusal)
    per_serving_classpath(endpoint, true) { |classpath, app| servlet_filter_decision(endpoint, classpath, app) }
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
