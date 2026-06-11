require "./pattern_definition"

module NoirAIContext
  # Detection catalogs consumed by `PatternMatcher` and the source
  # scan. Each constant is a list of `PatternDefinition`s (or a bare
  # regex for the order-independent CORS check). Defined at module
  # scope so `Builder` references them unqualified via Crystal's
  # lexical constant lookup, while keeping the catalog separate from
  # the orchestration logic.

  SINK_PATTERNS = [
    PatternDefinition.new(
      "data_store_query",
      "Potential database or graph/document-store query sink inferred from code or callee name",
      76,
      name_patterns: [/\b(?:mongo|client|neo4jClient)\.query\b/i],
      source_patterns: [/\b(?:mongo|client|neo4jClient)\.query\s*(?:<|\()/i]
    ),
    PatternDefinition.new(
      "sql",
      "Potential SQL/data-store sink inferred from code or callee name",
      78,
      name_patterns: [/raw_?sql/i, /find_?by_?sql/i, /\bquery\b/i, /\bexecute\b/i, /\bselect\b/i],
      source_patterns: [/find_by_sql/i, /\braw(sql|_sql)\b/i, /\bselect\b.+\bfrom\b/i, /\bexecute(Query|Sql)?\b/i]
    ),
    PatternDefinition.new(
      "command_exec",
      "Potential command execution sink inferred from code or callee name",
      82,
      name_patterns: [/\bexec\b/i, /\bsystem\b/i, /\bspawn\b/i, /\bpopen\b/i, /\bshell\b/i],
      source_patterns: [/\bexec\s*\(/i, /\bsystem\s*\(/i, /\bspawn\s*\(/i, /\bpopen\s*\(/i, /ProcessBuilder/i, /Runtime\.getRuntime/i, /subprocess\./i]
    ),
    PatternDefinition.new(
      "file_io",
      "Potential file I/O sink inferred from code or callee name",
      68,
      name_patterns: [/\bfile\b/i, /\bread\b/i, /\bupload\b/i, /\bdownload\b/i],
      source_patterns: [/\bFile\.(open|read|write)/, /\bread(File|_text)\b/i, /\bwrite(File|_text)\b/i, /\bsend_file\b/i, /\bsendFile\b/i, /\bdownload\b/i, /\bupload\b/i]
    ),
    PatternDefinition.new(
      "redirect",
      "Potential redirect sink inferred from code or callee name",
      74,
      name_patterns: [/\bredirect\b/i, /\bredirect_to\b/i],
      source_patterns: [/\bredirect(_to)?\s*\(/i, /\bres\.redirect\b/i, /Response\.Redirect/i]
    ),
    PatternDefinition.new(
      "template_render",
      "Potential template/render sink inferred from code or callee name",
      62,
      name_patterns: [/\brender\b/i, /\btemplate\b/i, /\bhtml\b/i, /\brespond\b/i],
      source_patterns: [/\brender(_template)?\s*\(/i, /\breturn\s+render\b/i, /\brespond_to\b/i]
    ),
    PatternDefinition.new(
      "outbound_http",
      "Potential outbound HTTP/client sink inferred from code or callee name",
      64,
      name_patterns: [
        /\b(?:reqwest|hyper|hyper_util|ureq|surf|isahc|attohttpc|awc)::[A-Za-z_][A-Za-z0-9_:!]*/i,
        /\bhttp\b/i,
        /\bfetch\b/i,
        /\bclient\b/i,
        /\baxios\b/i,
        /\bgetForObject\b/i,
        /\bexchange\b/i,
      ],
      source_patterns: [
        /requests\.(get|post|put|delete)/i,
        /\bfetch\s*\(/i,
        /\baxios\./i,
        /\bhttp\.(Get|Post|NewRequest)/,
        /\bclient\.(get|post|request)/i,
        /\b\w+\.(getForObject|postForObject|exchange)\s*\(/i,
        /\b(?:reqwest|ureq|surf|isahc|attohttpc)::(?:get|post|put|delete|patch|request)\s*(?:::<[^>]+>)?\s*\(/i,
        /\b(?:hyper|hyper_util|awc)::[A-Za-z0-9_:]*Client\b/,
      ]
    ),
    # ----- New in v1.1 (--ai-context coverage expansion) -----
    #
    # XSS / unsafe-HTML output. Catches assignments and helpers that
    # bypass the framework's auto-escaping (innerHTML, React's
    # dangerouslySetInnerHTML, Rails' html_safe / raw, Django /
    # Jinja's |safe + mark_safe / Markup, Vue's v-html, Svelte's
    # {@html ...}).
    PatternDefinition.new(
      "xss",
      "Potential XSS sink — unsafe HTML output bypassing the framework's auto-escaping",
      75,
      name_patterns: [/\bhtml_safe\b/i, /\bmark_safe\b/i, /\bdangerouslySetInnerHTML\b/, /\bformat_html\b/i],
      source_patterns: [
        /\.innerHTML\s*=/,
        /\.outerHTML\s*=/,
        /\bdocument\.write\s*\(/,
        /\bdangerouslySetInnerHTML\b/,
        /\{@html\b/,
        /\bv-html\b/,
        /\bMarkup\s*\(/,
        /\bmark_safe\s*\(/,
        /\|\s*safe\b/,
        /\.html_safe\b/,
        /\braw\s*\(/i,
        /\bbypassSecurityTrust(Html|Script|Style|Url|ResourceUrl)\b/,
      ]
    ),
    # Unsafe deserialization. RCE-class — anything that revives an
    # attacker-controlled byte stream into a live object graph.
    PatternDefinition.new(
      "deserialization",
      "Potential unsafe deserialization — attacker-controlled bytes revive into a live object graph (RCE class)",
      86,
      name_patterns: [/\bpickle\.loads\b/, /\bcPickle\.loads\b/, /\bdill\.loads\b/, /\bjsonpickle\.decode\b/, /\bunserialize\b/, /\bMarshal\.load\b/, /\breadObject\b/],
      source_patterns: [
        /\bpickle\.loads\s*\(/,
        /\bcPickle\.loads\s*\(/,
        /\bdill\.loads\s*\(/,
        /\bjsonpickle\.decode\s*\(/,
        /\byaml\.load\s*\(/, # yaml.load without SafeLoader
        /\bMarshal\.load\s*\(/,
        /\bunserialize\s*\(/,
        /\bObjectInputStream\b.*\breadObject\b/m,
        /\bXMLDecoder\b/,
        /\bXStream\b.*\bfromXML\b/,
        /\bBinaryFormatter\b.*\bDeserialize\b/,
        /\bLosFormatter\b/,
        /\bnode-serialize\b/,
      ]
    ),
    # Server-side template injection. Distinct from template_render —
    # SSTI specifically means the *template string itself* is built
    # from user input. The patterns look for template-from-string
    # constructors and `render_template_string`-style calls.
    PatternDefinition.new(
      "template_injection",
      "Potential server-side template injection (SSTI) — template string itself may be attacker-controlled",
      80,
      name_patterns: [/\brender_template_string\b/, /\bfrom_string\b/, /\bTemplate\.compile\b/],
      source_patterns: [
        /\brender_template_string\s*\(/,
        /\bEnvironment\(\)\.from_string\s*\(/,
        /\bjinja2\.Template\s*\(/,
        /\bERB\.new\s*\(/,
        /\bLiquid::Template\.parse\s*\(/,
        /\bHandlebars\.compile\s*\(/,
        /\b_\.template\s*\(/,
        /\bVelocity\.evaluate\s*\(/,
      ]
    ),
    # In-process code evaluation. Sibling of command_exec but stays
    # inside the runtime — eval / exec / Function() / instance_eval.
    PatternDefinition.new(
      "code_eval",
      "Potential in-process code evaluation — attacker-controlled source executed by the runtime (RCE class)",
      84,
      name_patterns: [/\binstance_eval\b/, /\bclass_eval\b/, /\bcreate_function\b/],
      source_patterns: [
        /\beval\s*\(/,
        /\bexec\s*\(/, # Python's exec (overlaps with shell exec but resolved by context)
        /\bcompile\s*\([^)]*,\s*['"]exec['"]/,
        /\bnew\s+Function\s*\(/,
        /\bFunction\s*\([^)]*\)\s*\(/,
        /\bsetTimeout\s*\(\s*['"]/, # setTimeout("string code", ...)
        /\bsetInterval\s*\(\s*['"]/,
        /\binstance_eval\s*\(/,
        /\bclass_eval\s*\(/,
        /\bbinding\.eval\s*\(/,
        /\bcreate_function\s*\(/,
        /\bassert\s*\(\s*\$/, # PHP assert($var) — eval-equivalent
        /\bScriptEngine\b.*\beval\b/,
      ]
    ),
    # Mass assignment — direct param/body → model write without
    # explicit field allowlist. Tunes confidence down because well-
    # structured apps with strong_params / DTO / Pydantic also
    # surface this shape and aren't necessarily vulnerable.
    PatternDefinition.new(
      "mass_assignment",
      "Potential mass-assignment — request params written into a model without an explicit field allowlist",
      60,
      name_patterns: [/\bupdate_attributes\b/, /\bassign_attributes\b/],
      source_patterns: [
        /\bupdate_attributes\s*\(/,
        /\bassign_attributes\s*\(/,
        /\.create\s*\(\s*params\b/,
        /\.create\s*\(\s*req\.body\b/,
        /\.update\s*\(\s*params\b/,
        /\.update\s*\(\s*req\.body\b/,
        /Object\.assign\s*\([^,]+,\s*req\.body\b/,
        /_\.merge\s*\([^,]+,\s*req\.body\b/,
      ]
    ),
    # Weak cryptography. Conservative — only flag when the snippet
    # also looks security-relevant (password / token / signature /
    # session). Plain MD5 on a cache key isn't worth flagging.
    PatternDefinition.new(
      "crypto_weak",
      "Potential weak cryptographic primitive in a security-relevant context (MD5/SHA1 for auth, DES, ECB, non-CSPRNG random)",
      56,
      name_patterns: [/\bDigest::MD5\b/, /\bDigest::SHA1\b/, /\bhashlib\.md5\b/, /\bhashlib\.sha1\b/, /\bMessageDigest\.getInstance\b/, /\b(?:Random|random)\.next(Int|Long|Bytes)?\b/],
      source_patterns: [
        /\bDigest::(MD5|SHA1)\b/,
        /\bhashlib\.(md5|sha1)\s*\(/,
        /\bMessageDigest\.getInstance\s*\(\s*['"](MD5|SHA-?1)['"]/,
        /\bCipher\.(getInstance|new)\s*\(\s*['"]DES/,
        /\bAES\/ECB\b/,
        /\bMode::ECB\b/,
        /\bRC4\b/,
        /\bMath\.random\s*\(\s*\)/,                             # JS non-CSPRNG
        /\bRandom\s*\(\s*\)\s*\.\s*next(Int|Long|Bytes)?\s*\(/, # JVM/Kotlin non-CSPRNG
      ]
    ),
    PatternDefinition.new(
      "webview_load",
      "WebView load of a potentially attacker-controlled URL/HTML — a deep-link XSS/SSRF surface on mobile",
      80,
      name_patterns: [/\.loadUrl\b/i, /\.loadData(WithBaseURL)?\b/i, /\.evaluateJavascript\b/i, /\b(?:wk)?web_?view\w*\??\.load\b/i],
      source_patterns: [/\.loadUrl\s*\(/i, /\.loadData(WithBaseURL)?\s*\(/i, /\.evaluateJavascript\s*\(/i, /\b(?:wk)?web_?view\w*\??\.load\s*\(/i, /\.load\s*\(\s*URLRequest/]
    ),
    PatternDefinition.new(
      "intent_redirect",
      "Intent launched from inbound deep-link data — intent redirection / component-hijack surface",
      70,
      name_patterns: [/\bstartActivity(ForResult)?\b/, /\bsendBroadcast\b/, /\bstartService\b/, /\bbindService\b/],
      source_patterns: [/\bstartActivity(ForResult)?\s*\(/, /\bsendBroadcast\s*\(/, /\bstartService\s*\(/]
    ),
  ] of PatternDefinition

  # Sink kinds that only make sense on a mobile deep-link endpoint — a
  # WebView load or an intent launch fed by inbound deep-link data. They
  # live in the global SINK_PATTERNS so the catalog stays in one place,
  # but the Builder evaluates them only for `endpoint.mobile?` endpoints:
  # an HTTP route handler never opens a WebView or launches an Android
  # intent, so firing these against every route is conceptually wrong
  # (and a latent FP source as the name/source patterns broaden).
  MOBILE_SINK_KINDS = Set{"webview_load", "intent_redirect"}

  # The non-mobile view of the sink catalog, computed once. Used for
  # HTTP endpoints so the two mobile-only sinks above are never matched
  # against server-side route/callee snippets.
  NON_MOBILE_SINK_PATTERNS = SINK_PATTERNS.reject { |pattern| MOBILE_SINK_KINDS.includes?(pattern.kind) }

  VALIDATOR_PATTERNS = [
    PatternDefinition.new(
      "validation",
      "Potential validation step inferred from code or callee name",
      64,
      name_patterns: [/\bvalidate\w*\b/i, /\bvalidator\w*\b/i, /\bverify\w*\b/i, /\bpermit\w*\b/i],
      source_patterns: [/\bvalidate\w*\s*\(/i, /\bvalidator\b/i, /\bpermit\s*\(/i, /\bverify\w*\s*\(/i]
    ),
    PatternDefinition.new(
      "expiry_validation",
      "Expiry/validity-window check inferred from token or session lifetime comparison",
      72,
      name_patterns: [/\b(expiry|expires?|expired|validUntil|notAfter)\w*\.(isBefore|isAfter)\b/i],
      source_patterns: [/\b(expiry|expires?|expired|validUntil|notAfter)\w*\s*\.\s*(isBefore|isAfter)\s*\(/i]
    ),
    PatternDefinition.new(
      "uniqueness_validation",
      "Uniqueness or duplicate-prevention validation inferred from guard helper naming",
      70,
      name_patterns: [
        /^checkIf\w*(Unique|Exists?|Duplicate)\w*OrThrow$/i,
        /^ensure\w*(Unique|Exists?|Duplicate)\w*$/i,
        /^assert\w*(Unique|Exists?|Duplicate)\w*$/i,
        /\b\w+(?:Repository|Repo|Dao)\.findBy(?!Id\b)(?!Id[A-Z])\w+\b/,
      ],
      source_patterns: [
        /\bcheckIf\w*(Unique|Exists?|Duplicate)\w*OrThrow\s*\(/i,
        /\bensure\w*(Unique|Exists?|Duplicate)\w*\s*\(/i,
        /\bassert\w*(Unique|Exists?|Duplicate)\w*\s*\(/i,
        /\b\w+(?:Repository|Repo|Dao)\.findBy(?!Id\b)(?!Id[A-Z])\w+\s*\([^\n]*\)[\s\S]{0,480}\b(?:isEmpty|isNotEmpty|isPresent|AlreadyExist|Duplicate|Unique)\b/i,
      ]
    ),
    PatternDefinition.new(
      "existence_validation",
      "Existence or duplicate-precondition check inferred from repository existence lookup",
      70,
      name_patterns: [/\b\w+Repository\.existsBy\w+\b/, /\b\w+Repo\.existsBy\w+\b/, /\b\w+Dao\.existsBy\w+\b/],
      source_patterns: [/\b\w+(?:Repository|Repo|Dao)\.existsBy\w+\s*\(/]
    ),
    PatternDefinition.new(
      "credential_hashing",
      "Credential hashing step inferred from Spring Security password encoder usage",
      74,
      name_patterns: [/\b(?:passwordEncoder|PasswordEncoder|BCryptPasswordEncoder|Argon2PasswordEncoder|Pbkdf2PasswordEncoder|SCryptPasswordEncoder)\.encode\b/]
    ),
    PatternDefinition.new(
      "credential_verification",
      "Credential verification step inferred from Spring Security password encoder usage",
      74,
      name_patterns: [/\b(?:passwordEncoder|PasswordEncoder|BCryptPasswordEncoder|Argon2PasswordEncoder|Pbkdf2PasswordEncoder|SCryptPasswordEncoder)\.matches\b/],
      source_patterns: [/\b\w*(?:PasswordEncoder|passwordEncoder)\w*\.matches\s*\(/]
    ),
    PatternDefinition.new(
      "cookie_httponly",
      "Cookie is configured HttpOnly, reducing client-side script access to session or refresh tokens",
      72,
      source_patterns: [/\b\w+\.isHttpOnly\s*=\s*true\b/, /\b\w+\.setHttpOnly\s*\(\s*true\s*\)/]
    ),
    PatternDefinition.new(
      "cookie_secure",
      "Cookie is configured Secure, restricting transport to HTTPS",
      72,
      source_patterns: [/\b\w+\.secure\s*=\s*true\b/, /\b\w+\.setSecure\s*\(\s*true\s*\)/]
    ),
    PatternDefinition.new(
      "query_parameter_binding",
      "Database query parameters are bound through the client API instead of string-concatenated into the query",
      74,
      source_patterns: [
        /\.bind\s*\([^)]*\)\s*\.to\s*\([^)]*\)/,
        /\.bind\s*\([^)]*\)\s*\.with\s*\{/,
        /\.bind\s*\(\s*\d+\s*,\s*[^)]*\)/,
      ]
    ),
    PatternDefinition.new(
      "sanitization",
      "Potential sanitization or escaping step inferred from code or callee name",
      68,
      name_patterns: [/\bsanitize\b/i, /\bescape\b/i, /\bencode\b/i, /\bnormalize\b/i, /\bclean\b/i],
      source_patterns: [/\bsanitize\w*\s*\(/i, /\bescape\w*\s*\(/i, /\bhtml_escape\b/i, /\bnormalize\w*\s*\(/i, /\bclean\w*\s*\(/i]
    ),
    # Schema-based validation — Pydantic / Zod / Joi / marshmallow /
    # JSON Schema. These give the strongest input-shape guarantee
    # because they reject any field outside the declared schema.
    # Worth a higher confidence than free-form validators.
    PatternDefinition.new(
      "schema_validation",
      "Schema-based input validation (strong shape guarantee — rejects fields outside the declared schema)",
      78,
      name_patterns: [/\bBaseModel\b/, /\bparse_obj\b/, /\bmodel_validate\b/, /\bz\.object\b/, /\bjoi\.object\b/i, /\bjsonschema\b/i, /\bmarshmallow\b/i],
      source_patterns: [
        # Class definitions — `class X(BaseModel)` / `pydantic.BaseModel`
        /\bclass\s+\w+\(\s*BaseModel\s*\)/,
        /\bpydantic\.BaseModel\b/,
        /\b\w+:\s*BaseModel\b/, # type hint `payload: BaseModel`
        # Pydantic call-site validation — works whether the model
        # is defined in the same file or imported.
        /\.parse_obj\s*\(/,
        /\.model_validate\s*\(/,
        /\.parse_raw\s*\(/,
        # Zod / Yup
        /\bz\.(object|string|number|array)\s*\(/,
        /\bschema\.parse\s*\(/,
        /\bYup\.(object|string|number)\b/,
        # Joi
        /\bjoi\.object\s*\(/i,
        /\bJoi\.validate\s*\(/,
        # marshmallow
        /\bSchema\(\)\.load\s*\(/,
        # JSON Schema
        /\bjsonschema\.validate\s*\(/,
        /\bvalidate\s*\(\s*\w+,\s*schema\s*\)/i,
      ]
    ),
    # Type coercion — parseInt / Integer / .to_i!. A weaker guard
    # than schema validation but still useful evidence that the
    # author considered the input type.
    PatternDefinition.new(
      "type_coercion",
      "Type coercion on input — narrower than schema validation but still constrains the value",
      50,
      name_patterns: [/\bparseInt\b/, /\bparseFloat\b/, /\bInteger\b/, /\bFloat\b/, /\btoInt\b/, /\bto_i!\b/],
      source_patterns: [
        /\bparseInt\s*\(/,
        /\bparseFloat\s*\(/,
        /\bInteger\s*\(/,
        /\bFloat\s*\(/,
        /\b\.to_i!\b/,
        /\b\.to_f!\b/,
        /\bNumber\s*\(/,
        /\bint\s*\(\s*request\./,
        /@(?:PathVariable|DestinationVariable|RequestParam|RequestHeader|CookieValue|Argument)(?:\s*\([^)]*\))?\s+(?:\w+\s*:\s*)?(?:U?Long|U?Int|Short|Byte|Double|Float|BigInteger|BigDecimal|UUID)\??(?=\b|[^A-Za-z0-9_])/,
        /@(?:PathVariable|DestinationVariable|RequestParam|RequestHeader|CookieValue|Argument)(?:\s*\([^)]*\))?\s+(?:final\s+)?(?:long|int|short|byte|double|float|Long|Integer|Short|Byte|Double|Float|BigInteger|BigDecimal|UUID)\s+\w+\b/,
      ]
    ),
    # Allowlist check — explicit `in ALLOWED` / `whitelist.include?`
    # / `permitted_values.contains`. Often the cleanest defence for
    # values where the legitimate set is small and known.
    PatternDefinition.new(
      "allowlist_check",
      "Allowlist / membership check — value compared against a known-good fixed set",
      62,
      name_patterns: [/\bwhitelist\b/i, /\ballowlist\b/i, /\bpermitted_values\b/i],
      source_patterns: [
        /\bwhitelist\b/i,
        /\ballowlist\b/i,
        /\ballowed[_-]?values\b/i,
        /\bpermitted_values\b/i,
        /\bif\s+\w+\s+in\s+[A-Z_][A-Z0-9_]+\b/, # `if value in ALLOWED_*`
        /\b\bALLOWED_[A-Z_]+\.(include|contains)/,
        /\.include\?\s*\(\s*\w+\s*\)\s*(?:or|\|\|)/, # very loose, low priority
        /\bin\s*\[[\w\s,'"]+\]/i,                    # `if v in ['a','b']`
      ]
    ),
  ] of PatternDefinition

  # ----- Guards -----
  #
  # Split into four narrow groups so the LLM (and human reviewers)
  # can tell *which* layer is protecting a route. A route with
  # authentication but no authorization is a privilege-escalation
  # candidate; a route with authentication but no CSRF protection
  # is a cross-site request candidate; etc.
  #
  # The legacy single `guard` kind was too coarse: a `before_action
  # :authenticate_user!` and a `before_action :authorize_admin!`
  # would both surface as the same flat "guard", losing the
  # distinction reviewers actually care about.

  # Authentication guard — "verifies who you are". Login required,
  # JWT verification, session check.
  AUTH_GUARD_PATTERNS = [
    PatternDefinition.new(
      "auth_guard",
      "Potential authentication guard — checks who the caller is",
      56,
      source_patterns: [
        /passport\.authenticate/i,
        /expressjwt/i,
        /\bauthenticate\w*\b/i,
        /\bverifyToken\b/i,
        /\brequireAuth\b/i,
        /\blogin_required\b/i,
        /\bjwt_required\b/i,
        /\brequire_login\b/i,
        /\blogged_in_user\b/i,
        /Depends\s*\(\s*get_current_/i,
        /before_action\s+:\w*auth/i,
        /\.Use\s*\(\s*\w*Auth\w*/i,
      ]
    ),
  ] of PatternDefinition

  # Authorization guard — "verifies what you can do". Role,
  # permission, ability, policy checks. Distinct from authentication
  # because the common security gap is "logged in but no further
  # check" → horizontal / vertical privilege escalation.
  AUTHZ_GUARD_PATTERNS = [
    PatternDefinition.new(
      "authz_guard",
      "Potential authorization guard — checks what the authenticated caller may do",
      60,
      source_patterns: [
        /\bauthorize\w*\b/i,
        /\bcheckPermission\b/i,
        /\bhasAuthority\b/i,
        /\brequiresRole\b/i,
        /\brole_required\b/i,
        /\badmin_required\b/i,
        /\brequire_role\b/i,
        /\brequire_any_role\b/i,
        /\brequire_all_roles\b/i,
        /\buser_has_role\b/i,
        /@PreAuthorize\b/,
        /@RolesAllowed\b/,
        /@Secured\b/,
        /Security\s*\(/,
        /\bPundit\b.*\bauthorize\b/i,
        /\bcan\?\s*\(/,
        /\b(can|cannot)\s+:[\w_!?]+/,
        /\bability\.\w+/i,
      ]
    ),
  ] of PatternDefinition

  # CSRF protection. Different layer from authn/authz — protects
  # against cross-site request forgery via tokens / SameSite cookies
  # / origin checks. Absent on state-changing endpoints is usually
  # worth a review note.
  CSRF_GUARD_PATTERNS = [
    PatternDefinition.new(
      "csrf_guard",
      "Potential CSRF protection — token check, SameSite cookie policy, or origin check",
      70,
      source_patterns: [
        /\bprotect_from_forgery\b/,
        /\bcsrf_token\b/,
        /\bcsrfProtection\b/,
        /\bCsrf(Token)?Filter\b/,
        /\bCSRFGuard\b/,
        /verify_authenticity_token/,
        /@csrf_protect\b/,
        /\bSameSite\b.*\bStrict\b/i,
      ]
    ),
  ] of PatternDefinition

  # Rate limiting / throttling. Often the only defence on
  # credential-handling endpoints against credential stuffing /
  # brute-force. Confidence is moderate because not every endpoint
  # needs rate limiting (only credential / lookup-style ones).
  RATE_LIMIT_GUARD_PATTERNS = [
    PatternDefinition.new(
      "rate_limit_guard",
      "Potential rate-limit / throttling layer",
      64,
      source_patterns: [
        /\bThrottle\b/,
        /\bRateLimiter\b/,
        /@limits?\s*\(/,
        /@limiter\b/,
        /\bflask[-_]limiter\b/i,
        /\bslowapi\b/i,
        /\bratelimit\b/i,
        /\.throttle\s*\(/,
        /Bucket(Token)?\b/,
      ]
    ),
  ] of PatternDefinition

  GUARD_PATTERN_GROUPS = [
    AUTH_GUARD_PATTERNS,
    AUTHZ_GUARD_PATTERNS,
    CSRF_GUARD_PATTERNS,
    RATE_LIMIT_GUARD_PATTERNS,
  ]

  # Negative protection: explicit CSRF bypass. Emit as a SIGNAL
  # (not a guard) so the LLM knows protection is intentionally
  # disabled here and the endpoint warrants extra scrutiny.
  CSRF_EXEMPT_PATTERNS = [
    PatternDefinition.new(
      "csrf_exempt",
      "Explicit CSRF protection bypass — review whether the exemption is justified",
      80,
      source_patterns: [
        /@csrf_exempt\b/,
        /\bcsrf_exempt\s*\(/,
        /protect_from_forgery\s+with:\s*:null_session/,
        /\.disable\s*\(\s*\.?csrf/i,
        /csrfProtection:\s*false/i,
        /@SuppressWarnings\(.*csrf.*\)/i,
      ]
    ),
  ] of PatternDefinition

  # JWT verification bypass — explicit "trust whatever we
  # received without checking" shapes across pyjwt / jsonwebtoken
  # / java-jwt / ruby-jwt. Each pattern is a single-line dead
  # giveaway, surfaced as a sharp signal alongside csrf_exempt /
  # cors_open. The kind is `jwt_unsafe` so consumers can sort it
  # next to csrf_exempt.
  JWT_UNSAFE_PATTERNS = [
    PatternDefinition.new(
      "jwt_unsafe",
      "JWT verification is disabled or weakened — token contents become attacker-controlled",
      82,
      source_patterns: [
        # pyjwt — `verify=False` / `verify_signature: False`
        # (quoted in dict literals: `"verify_signature": False`).
        # The optional `['"]?` before the colon handles JSON-style
        # key quoting.
        /\bjwt\.decode\s*\([^)]*verify\s*=\s*False/i,
        /\bverify_signature['"]?\s*:\s*False/i,
        /\bverify_signature\s*=\s*False/i,
        # algorithm "none" — pyjwt / jsonwebtoken / java-jwt
        /algorithms?['"]?\s*[:=]\s*\[?\s*['"]none['"]/i,
        /algorithm['"]?\s*[:=]\s*['"]none['"]/i,
        # jsonwebtoken (node) — ignoreExpiration weakens validation
        /ignoreExpiration['"]?\s*:\s*true/i,
        # java-jwt — Algorithm.none()
        /Algorithm\.none\s*\(/,
        # ruby-jwt — verify: false / verify => false
        /\bJWT\.decode\s*\([^)]*verify\s*=>\s*false/i,
        /\bJWT\.decode\s*\([^)]*verify:\s*false/i,
      ]
    ),
  ] of PatternDefinition

  # CORS open-with-credentials. Wildcard `*` origin combined with
  # `credentials: true` is the textbook CORS misconfiguration —
  # browsers actually block this combination at the spec level for
  # security reasons, so seeing it in code means either the
  # config is broken or the developer is reaching for something
  # the spec forbids. Either way, worth a sharp signal.
  #
  # The check is order-independent across two regex windows so
  # `origin: '*'` followed by `credentials: true` and the reverse
  # both fire.
  CORS_WILDCARD_PATTERN    = /\b(?:origin|origins?)\s*[:=]\s*['"]\*['"]/i
  CORS_CREDENTIALS_PATTERN = /\b(?:credentials|allow[_-]?credentials|allowCredentials)\s*[:=]\s*(?:true|['"]true['"])/i

  PARAM_PATTERNS = [
    PatternDefinition.new(
      "credential_input",
      "Credential-bearing input; review secret handling, logging, and auth bypass paths",
      86,
      name_patterns: [/\b(pass(word)?|token|secret|api[_-]?key|authorization|session|cookie|jwt|bearer)\b/i]
    ),
    PatternDefinition.new(
      "identifier_input",
      "Identifier-like input frequently drives authorization and object lookup decisions",
      74,
      name_patterns: [/\bid\b/i, /\buser(_id)?\b/i, /\baccount(_id)?\b/i, /\border(_id)?\b/i, /\bprofile\b/i, /\bdoc(ument)?\b/i, /\bproject(_id)?\b/i]
    ),
    PatternDefinition.new(
      "redirect_input",
      "Redirect or callback-like input may affect navigation or outbound requests",
      76,
      name_patterns: [/\b(url|uri|redirect|return|next|continue|dest|destination|callback)\b/i]
    ),
    PatternDefinition.new(
      "file_input",
      "File-like input may influence upload, download, or path traversal behavior",
      78,
      name_patterns: [/\b(file|upload|attachment|image|document|filename|filepath|path)\b/i]
    ),
    PatternDefinition.new(
      "query_builder_input",
      "Query-builder-like input can influence filtering, sorting, or data access clauses",
      70,
      name_patterns: [/\b(sort|order|filter|where|search|select|field|column)\b/i]
    ),
    # PII (personally identifiable info). Worth a review note for
    # storage / logging / retention even when no specific sink is
    # nearby. Confidence high — these names rarely co-opt for
    # unrelated purposes.
    PatternDefinition.new(
      "pii_input",
      "Personally identifiable information; review storage, logging, retention, and access controls",
      78,
      name_patterns: [/\b(email|e[-_]?mail|phone|mobile|ssn|tax[_-]?id|dob|date[_-]?of[_-]?birth|birthdate|nin|national[_-]?id|passport|driver[_-]?license)\b/i]
    ),
    # Rich content fields. Common XSS source — body / description /
    # comment / markdown almost always flow into a render path and
    # need either escaping or a strict schema.
    PatternDefinition.new(
      "html_content_input",
      "Rich-content input may flow into HTML output; review escaping or schema validation",
      72,
      name_patterns: [
        /\b(body|description|html|message|comment|note|memo|markdown|rich[_-]?text)\b/i,
        /\b(html[_-]?content|content[_-]?html|markdown[_-]?content|content[_-]?markdown|rich[_-]?content|content[_-]?rich)\b/i,
      ]
    ),
    # Code / formula / template fields. High-risk XSS+SSTI+eval
    # source class. If an endpoint accepts these names, the
    # downstream sinks deserve closer scrutiny.
    PatternDefinition.new(
      "code_input",
      "Code/script-like input often flows into eval, template, or interpreter sinks",
      80,
      name_patterns: [
        /\b(script|formula|expression|command|cmd|template|query[_-]?string)\b/i,
        /\b(source[_-]?code|script[_-]?code|template[_-]?code|code[_-]?(snippet|block|body|source))\b/i,
      ]
    ),
  ] of PatternDefinition
end
