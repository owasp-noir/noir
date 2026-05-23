require "../models/endpoint"

module NoirAIContext
  extend self

  def apply(endpoints : Array(Endpoint)) : Array(Endpoint)
    Builder.new.apply(endpoints)
  end

  private class PatternDefinition
    getter kind : String
    getter description : String
    getter confidence : Int32
    getter name_patterns : Array(Regex)
    getter source_patterns : Array(Regex)

    def initialize(@kind : String,
                   @description : String,
                   @confidence : Int32,
                   *,
                   @name_patterns : Array(Regex) = [] of Regex,
                   @source_patterns : Array(Regex) = [] of Regex)
    end
  end

  private class Builder
    ROUTE_SNIPPET_RADIUS  =   2
    SOURCE_SCAN_RADIUS    =   6
    CALLEE_SNIPPET_RADIUS =   1
    MAX_SNIPPET_CHARS     = 240
    MAX_ROUTE_SCOPE_LINES =  12

    STATE_CHANGING_METHODS = Set{"POST", "PUT", "PATCH", "DELETE"}
    BODY_LIKE_PARAM_TYPES  = Set{"json", "form"}

    SINK_PATTERNS = [
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
        name_patterns: [/\bhttp\b/i, /\bfetch\b/i, /\bclient\b/i, /\baxios\b/i],
        source_patterns: [/requests\.(get|post|put|delete)/i, /\bfetch\s*\(/i, /\baxios\./i, /\bhttp\.(Get|Post|NewRequest)/, /\bclient\.(get|post|request)/i]
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
          /\byaml\.load\s*\(/,         # yaml.load without SafeLoader
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
          /\bexec\s*\(/,                  # Python's exec (overlaps with shell exec but resolved by context)
          /\bcompile\s*\([^)]*,\s*['"]exec['"]/,
          /\bnew\s+Function\s*\(/,
          /\bFunction\s*\([^)]*\)\s*\(/,
          /\bsetTimeout\s*\(\s*['"]/,     # setTimeout("string code", ...)
          /\bsetInterval\s*\(\s*['"]/,
          /\binstance_eval\s*\(/,
          /\bclass_eval\s*\(/,
          /\bbinding\.eval\s*\(/,
          /\bcreate_function\s*\(/,
          /\bassert\s*\(\s*\$/,           # PHP assert($var) — eval-equivalent
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
        name_patterns: [/\bDigest::MD5\b/, /\bDigest::SHA1\b/, /\bhashlib\.md5\b/, /\bhashlib\.sha1\b/, /\bMessageDigest\.getInstance\b/],
        source_patterns: [
          /\bDigest::(MD5|SHA1)\b/,
          /\bhashlib\.(md5|sha1)\s*\(/,
          /\bMessageDigest\.getInstance\s*\(\s*['"](MD5|SHA-?1)['"]/,
          /\bCipher\.(getInstance|new)\s*\(\s*['"]DES/,
          /\bAES\/ECB\b/,
          /\bMode::ECB\b/,
          /\bRC4\b/,
          /\bMath\.random\s*\(\s*\)/,                # JS non-CSPRNG
        ]
      ),
    ] of PatternDefinition

    VALIDATOR_PATTERNS = [
      PatternDefinition.new(
        "validation",
        "Potential validation step inferred from code or callee name",
        64,
        name_patterns: [/\bvalidate\b/i, /\bvalidator\b/i, /\bverify\b/i, /\bpermit\b/i],
        source_patterns: [/\bvalidate\w*\s*\(/i, /\bvalidator\b/i, /\bpermit\s*\(/i, /\bverify\w*\s*\(/i]
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
          /\b\w+:\s*BaseModel\b/,                      # type hint `payload: BaseModel`
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
          /\bif\s+\w+\s+in\s+[A-Z_][A-Z0-9_]+\b/,      # `if value in ALLOWED_*`
          /\b\bALLOWED_[A-Z_]+\.(include|contains)/,
          /\.include\?\s*\(\s*\w+\s*\)\s*(?:or|\|\|)/,  # very loose, low priority
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
        name_patterns: [/\b(content|body|description|html|message|comment|note|memo|markdown|rich[_-]?text)\b/i]
      ),
      # Code / formula / template fields. High-risk XSS+SSTI+eval
      # source class. If an endpoint accepts these names, the
      # downstream sinks deserve closer scrutiny.
      PatternDefinition.new(
        "code_input",
        "Code/script-like input often flows into eval, template, or interpreter sinks",
        80,
        name_patterns: [/\b(script|code|formula|expression|command|cmd|template|query[_-]?string)\b/i]
      ),
    ] of PatternDefinition

    @file_cache : Hash(String, Array(String))

    def initialize
      @file_cache = {} of String => Array(String)
    end

    def apply(endpoints : Array(Endpoint)) : Array(Endpoint)
      endpoints.map! do |endpoint|
        context = build_context(endpoint)
        endpoint.ai_context = context.empty? ? nil : context
        endpoint
      end

      endpoints
    end

    private def build_context(endpoint : Endpoint) : AIContext
      context = AIContext.new
      anchor = endpoint.details.code_paths.first?
      route_snippet = snippet_for(anchor.try(&.path), anchor.try(&.line), ROUTE_SNIPPET_RADIUS)

      add_route_signal(context, endpoint, anchor, route_snippet)
      add_technology_signal(context, endpoint, anchor, route_snippet)
      add_method_signal(context, endpoint, anchor, route_snippet)
      add_internal_signal(context, endpoint, anchor, route_snippet)
      add_param_signals(context, endpoint, anchor, route_snippet)
      add_tag_entries(context, endpoint, anchor, route_snippet)
      add_callee_entries(context, endpoint)
      add_source_scan_entries(context, endpoint)
      add_credential_from_source_signal(context, endpoint, anchor)
      add_missing_guard_signal(context, endpoint, anchor, route_snippet)
      add_combination_signals(context, endpoint, anchor, route_snippet)

      context
    end

    # Derived signals that depend on multiple primary signals being
    # present. Run last so every prior populate step has a chance to
    # contribute.
    private def add_combination_signals(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      add_open_redirect_signal(context, anchor, route_snippet)
      add_sensitive_response_signal(context, endpoint, anchor, route_snippet)
      add_unsafe_method_signal(context, endpoint, anchor, route_snippet)
      add_log_injection_signal(context, endpoint, anchor, route_snippet)
      add_priority_review_signal(context, endpoint, anchor, route_snippet)
    end

    # Concrete review-worthy signal kinds. These are the "this is
    # actually scary" categories — not the structural ones
    # (`route_definition`, `technology`, `path_param`) that every
    # endpoint surfaces.
    REVIEW_PRIORITY_SIGNAL_KINDS = Set{
      "guard_absence",
      "authz_absence",
      "rate_limit_absence",
      "idor_review",
      "csrf_exempt",
      "open_redirect",
      "sensitive_response",
      "unsafe_method",
      "log_injection",
    }

    # Categories whose mere presence is a security-review signal —
    # used alongside concrete signals to compute the overall
    # priority bucket.
    PRIORITY_SCORING_SINK_BLACKLIST = Set{
      "sql", "command_exec", "code_eval", "deserialization",
      "template_injection", "xss", "mass_assignment", "crypto_weak",
    }

    # Roll-up "this endpoint deserves attention" hint. Counts the
    # concrete review-worthy signals and sink kinds the augmentor
    # already raised, and emits one of three buckets — high / medium
    # / low — so an LLM (or a human triage pass) can sort the JSON
    # output by priority without re-implementing the scoring.
    #
    # Confidence is fixed per bucket (high / medium / low) so the
    # signal stays trivially filterable: `select(.confidence >= 80)`
    # gives just the high-priority routes.
    private def add_priority_review_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return if context.signals.any? { |s| s.kind == "priority_review" }

      review_signals = context.signals.count { |s| REVIEW_PRIORITY_SIGNAL_KINDS.includes?(s.kind) }
      heavy_sinks = context.sinks.count { |s| PRIORITY_SCORING_SINK_BLACKLIST.includes?(s.kind) }

      score = review_signals + heavy_sinks
      # `csrf_exempt` and `open_redirect` are individually loud
      # enough to bump the bucket even when other signals are quiet.
      sharp_signal = context.signals.any? do |s|
        s.kind == "csrf_exempt" || s.kind == "open_redirect"
      end
      score += 1 if sharp_signal

      return if score < 2 # don't pollute every endpoint with low-signal entries

      # Threshold rationale: a "missing guard + dangerous sink" pair
      # (e.g. guard_absence + sql sink, score=2) is the classic
      # textbook signal. We want that to surface, but not as "high"
      # — high is reserved for stacked risk (multiple missing
      # protections AND a sink, or a sharp signal like csrf_exempt
      # / open_redirect already screaming for attention).
      bucket = if score >= 3 || (sharp_signal && score >= 2) || heavy_sinks >= 2
                 {name: "high", confidence: 90,
                  description: "High-priority review candidate — multiple risk signals stack on this endpoint (combination of missing guards, dangerous sinks, or explicit protection bypasses)."}
               else
                 {name: "medium", confidence: 70,
                  description: "Medium-priority review candidate — at least one missing guard and one risky sink (or equivalent) co-occur on this endpoint."}
               end

      context.push_signal(AIContextEntry.new(
        "priority_review",
        bucket[:name],
        source: "heuristic",
        description: bucket[:description].as(String),
        path: anchor.try(&.path),
        line: anchor.try(&.line),
        confidence: bucket[:confidence].as(Int32),
        snippet: route_snippet
      ))
    end

    # HTTP method intent vs implementation mismatch. A GET/HEAD
    # endpoint that mutates server state through a callee
    # (`User.create`, `record.destroy`, `db.delete`, …) is a textbook
    # CSRF / side-effect-on-read bug — the verb says "safe / idempotent"
    # but the code says otherwise.
    SAFE_METHODS = Set{"GET", "HEAD", "OPTIONS"}

    MUTATING_CALLEE_PATTERN = /\b(create|destroy|delete|update|save|insert|remove|drop|truncate|write|push|append|persist|flush|commit|rollback|set_\w+)\b/i

    private def add_unsafe_method_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return unless SAFE_METHODS.includes?(endpoint.method)
      return if context.signals.any? { |s| s.kind == "unsafe_method" }

      mutating = endpoint.callees.find { |c| c.name.matches?(MUTATING_CALLEE_PATTERN) }
      return unless mutating

      context.push_signal(AIContextEntry.new(
        "unsafe_method",
        "#{endpoint.method} → #{mutating.name}",
        source: "heuristic",
        description: "Safe-method (GET/HEAD/OPTIONS) endpoint invokes a state-changing callee; CSRF protections typically don't gate read methods, so a mutation through one is suspect.",
        path: mutating.path || anchor.try(&.path),
        line: mutating.line || anchor.try(&.line),
        confidence: 56,
        snippet: route_snippet
      ))
    end

    # Log injection / sensitive data in logs. Catches the canonical
    # "log user input or credential field directly" shape. False
    # positives are bounded because both the log call AND a user-
    # input reference (or credential noun) need to be on the same
    # line / snippet window.
    LOG_EMITTER_PATTERN = /\b(?:logger\.(?:info|warn|warning|error|debug|critical|fatal)|log\.(?:info|warn|warning|error|debug)|console\.(?:log|info|warn|error|debug)|print|puts|printf|System\.out\.println|Log\.[dwiev])\b/i

    LOG_INPUT_OR_CRED_PATTERN = /\b(?:req\.body|req\.query|req\.params|request\.form|request\.json|request\.args|params\[|password|passwd|token|secret|api[_-]?key|jwt|session_id|access_token|refresh_token)\b/i

    private def add_log_injection_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return if context.signals.any? { |s| s.kind == "log_injection" }
      return if endpoint.details.code_paths.empty?

      endpoint.details.code_paths.each do |path_info|
        scope = route_scope_snippet_for(path_info.path, path_info.line)
        next unless scope
        next unless scope.matches?(LOG_EMITTER_PATTERN)
        next unless scope.matches?(LOG_INPUT_OR_CRED_PATTERN)

        context.push_signal(AIContextEntry.new(
          "log_injection",
          "log+input",
          source: "route_source",
          description: "Handler logs request-controlled or credential-bearing data; review for log-injection (newline/control-char smuggling) and sensitive-data leakage into log sinks.",
          path: path_info.path,
          line: path_info.line,
          confidence: 50,
          snippet: scope
        ))
        return
      end
    end

    # Open-redirect candidate: handler has a redirect sink AND
    # accepts a redirect-like input (url / uri / next / dest /
    # callback / return / continue). Either alone is normal; the
    # combination is the textbook open-redirect signature.
    private def add_open_redirect_signal(context : AIContext, anchor : PathInfo?, route_snippet : String?)
      return unless context.sinks.any? { |s| s.kind == "redirect" }
      return unless context.signals.any? { |s| s.kind == "redirect_input" }
      return if context.signals.any? { |s| s.kind == "open_redirect" }

      redirect_sink = context.sinks.find { |s| s.kind == "redirect" }.not_nil!
      context.push_signal(AIContextEntry.new(
        "open_redirect",
        redirect_sink.name,
        source: "heuristic",
        description: "Handler redirects using a user-controlled-looking input — classic open-redirect signature. Review whether the destination is validated against an allowlist.",
        path: anchor.try(&.path) || redirect_sink.path,
        line: anchor.try(&.line) || redirect_sink.line,
        confidence: 72,
        snippet: route_snippet || redirect_sink.snippet
      ))
    end

    # Sensitive-response detection runs as a two-step check on the
    # route-scope snippet:
    #
    #   1. RESPONSE_EMITTER_PATTERN — the snippet calls a response-
    #      serializing helper (`res.json`, `jsonify`, `render json:`,
    #      `to_json`, `JsonResponse`, …).
    #   2. CREDENTIAL_KEY_IN_RESPONSE — the snippet also has a
    #      credential noun *as a key* (followed by `:`, and not
    #      preceded by a quote or word character — so the noun
    #      appearing inside a string value like
    #      `{ message: "Set X-API-KEY header" }` doesn't fire).
    #
    # Both have to match in the same scope. The earlier single-regex
    # version was too loose and caught english prose mentioning
    # credentials in response strings.
    RESPONSE_EMITTER_PATTERN = /\b(jsonify|res\.json|json_response|JsonResponse|render\s+json:|to_json|respond_with)\b/i
    CREDENTIAL_KEY_IN_RESPONSE = /[^"'\w](password|passwd|token|secret|api[_-]?key|session_id|access_token|refresh_token|private_key)\s*:/i

    private def add_sensitive_response_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return if context.signals.any? { |s| s.kind == "sensitive_response" }
      return if endpoint.details.code_paths.empty?

      endpoint.details.code_paths.each do |path_info|
        scope = route_scope_snippet_for(path_info.path, path_info.line)
        next unless scope
        next unless scope.matches?(RESPONSE_EMITTER_PATTERN)
        if match = scope.match(CREDENTIAL_KEY_IN_RESPONSE)
          field = match[1]? || "credential"
          context.push_signal(AIContextEntry.new(
            "sensitive_response",
            field.downcase,
            source: "route_source",
            description: "Response body appears to include a credential-bearing field; review whether it's intentional and whether the field is stripped/masked for the caller's role.",
            path: path_info.path,
            line: path_info.line,
            confidence: 68,
            snippet: scope
          ))
          return
        end
      end
    end

    # Some analyzers (express's loose destructuring, Java route extractors
    # that don't follow `@RequestBody Credentials c.password`, …) miss
    # credential-bearing parameters at extract time. When that happens
    # the param-based credential_input signal never fires and downstream
    # heuristics like rate_limit_absence silently skip the route.
    #
    # As a backstop, scan the route-scope snippet for the canonical
    # request-body destructuring shapes (`req.body.password`,
    # `request.form['password']`, `{ password } = req.body`, …) and
    # emit a credential_input signal with a slightly lower confidence
    # than the param-based one. The kind is the same so downstream
    # rate_limit_absence / guard_absence logic catches it transparently.
    CREDENTIAL_SOURCE_PATTERNS = [
      # JS/TS destructuring: `const { password, token } = req.body`
      /(?:const|let|var)\s*\{[^}]*\b(password|passwd|token|secret|api[_-]?key|jwt|bearer)\b[^}]*\}\s*=\s*req\.body/i,
      # JS member access: `req.body.password`, `req.body.token`, …
      /\breq\.body\.(password|passwd|token|secret|api[_-]?key|jwt|bearer)\b/i,
      # Python form/json access: `request.form['password']`, `request.json['token']`
      /\brequest\.(form|json|data)\[\s*['"](password|passwd|token|secret|api[_-]?key|jwt|bearer)['"]/i,
      # Python attribute access (FastAPI / DRF): `payload.password`,
      # `credentials.token` — tighter scope so generic `.password`
      # access doesn't fire.
      /\b(payload|credentials|creds|input|body)\.(password|passwd|token|secret|api[_-]?key|jwt|bearer)\b/i,
      # Java/Kotlin field access on a DTO marked @RequestBody: `c.password`
      # is too generic alone; require the credential noun directly.
      /\b(password|passwd|token|secret|api[_-]?key|jwt|bearer)\s*=\s*req\./i,
    ]

    private def add_credential_from_source_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?)
      return if context.signals.any? { |s| s.kind == "credential_input" }
      return if endpoint.details.code_paths.empty?

      endpoint.details.code_paths.each do |path_info|
        snippet = route_scope_snippet_for(path_info.path, path_info.line)
        next unless snippet

        CREDENTIAL_SOURCE_PATTERNS.each do |pattern|
          if match = snippet.match(pattern)
            captured = match[1]? || match[0]
            context.push_signal(AIContextEntry.new(
              "credential_input",
              "source.#{captured.downcase}",
              source: "route_source",
              description: "Credential-like identifier observed in handler body (analyzer did not surface it as a parameter); review secret handling and auth bypass paths.",
              path: path_info.path,
              line: path_info.line,
              confidence: 64,
              snippet: snippet
            ))
            return # one credential_input from source is enough
          end
        end
      end
    end

    private def add_route_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      context.push_signal(AIContextEntry.new(
        "route_definition",
        "#{endpoint.method} #{endpoint.url}",
        source: "route",
        description: "Primary route registration or controller entrypoint",
        path: anchor.try(&.path),
        line: anchor.try(&.line),
        confidence: 100,
        snippet: route_snippet
      ))
    end

    private def add_technology_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return unless technology = endpoint.details.technology

      context.push_signal(AIContextEntry.new(
        "technology",
        technology,
        source: "detector",
        description: "Detected framework or language technology for this endpoint",
        path: anchor.try(&.path),
        line: anchor.try(&.line),
        confidence: 96,
        snippet: route_snippet
      ))
    end

    private def add_method_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return unless STATE_CHANGING_METHODS.includes?(endpoint.method)

      description = case endpoint.method
                    when "DELETE"
                      "State-changing delete endpoint; review authorization, ownership, and destructive side effects"
                    else
                      "State-changing endpoint; review authz, validation, and side effects"
                    end

      context.push_signal(AIContextEntry.new(
        "state_change",
        endpoint.method,
        source: "http_method",
        description: description,
        path: anchor.try(&.path),
        line: anchor.try(&.line),
        confidence: 88,
        snippet: route_snippet
      ))
    end

    private def add_internal_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return unless endpoint.internal

      context.push_signal(AIContextEntry.new(
        "internal_endpoint",
        "#{endpoint.method} #{endpoint.url}",
        source: "endpoint",
        description: "Analyzer marked this endpoint as internal-only or non-public",
        path: anchor.try(&.path),
        line: anchor.try(&.line),
        confidence: 78,
        snippet: route_snippet
      ))
    end

    private def add_param_signals(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      endpoint.params.each do |param|
        add_path_param_signal(context, param, anchor, route_snippet)

        PARAM_PATTERNS.each do |pattern|
          next unless matches_any?(param.name, pattern.name_patterns)
          next if skip_param_signal?(endpoint, param, pattern)
          next if redundant_param_signal?(param, pattern)

          description = if param.param_type == "path" && pattern.kind == "identifier_input"
                          "Path parameter selects a server-side resource; review authorization and ownership checks"
                        else
                          pattern.description
                        end

          context.push_signal(AIContextEntry.new(
            pattern.kind,
            "#{param.param_type}.#{param.name}",
            source: "param",
            description: description,
            path: anchor.try(&.path),
            line: anchor.try(&.line),
            confidence: pattern.confidence,
            snippet: route_snippet
          ))
        end

        param.tags.each do |tag|
          context.push_signal(AIContextEntry.new(
            tag.name,
            "#{param.param_type}.#{param.name}",
            source: "param_tagger:#{tag.tagger}",
            description: "#{tag.description} Matched by parameter-name heuristic.",
            path: anchor.try(&.path),
            line: anchor.try(&.line),
            confidence: 58,
            snippet: route_snippet
          ))
        end
      end
    end

    private def skip_param_signal?(endpoint : Endpoint, param : Param, pattern : PatternDefinition) : Bool
      return true if pattern.kind == "file_input" && param.param_type == "header"
      return false unless pattern.kind == "identifier_input"
      return !header_identifier_like?(param.name) if param.param_type == "header"
      return false unless BODY_LIKE_PARAM_TYPES.includes?(param.param_type)
      param.name == "id"
    end

    private def redundant_param_signal?(param : Param, pattern : PatternDefinition) : Bool
      case pattern.kind
      when "query_builder_input"
        param.tags.any? { |tag| tag.name == "sqli" }
      when "identifier_input"
        param.param_type == "path" && param.tags.any? { |tag| tag.name == "idor" }
      else
        false
      end
    end

    private def add_path_param_signal(context : AIContext, param : Param, anchor : PathInfo?, route_snippet : String?)
      return unless param.param_type == "path"

      context.push_signal(AIContextEntry.new(
        "path_param",
        param.name,
        source: "param",
        description: "Path parameter participates in route selection and often controls object lookup",
        path: anchor.try(&.path),
        line: anchor.try(&.line),
        confidence: 84,
        snippet: route_snippet
      ))
    end

    private def add_tag_entries(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      endpoint.tags.each do |tag|
        entry = AIContextEntry.new(
          guard_tag?(tag) ? "auth_guard" : tag.name,
          guard_tag?(tag) ? guard_name_from_tag(tag) : tag.name,
          source: tag.tagger,
          description: tag.description,
          path: anchor.try(&.path),
          line: anchor.try(&.line),
          confidence: tag.name == "auth" ? 86 : 74,
          snippet: route_snippet
        )

        if guard_tag?(tag)
          context.push_guard(entry)
        else
          context.push_signal(entry)
          if tag.name == "file_upload"
            context.push_sink(AIContextEntry.new(
              "file_io",
              "file_upload",
              source: tag.tagger,
              description: "Endpoint characteristics suggest file upload or file handling behavior",
              path: anchor.try(&.path),
              line: anchor.try(&.line),
              confidence: 80,
              snippet: route_snippet
            ))
          end
        end
      end
    end

    private def add_callee_entries(context : AIContext, endpoint : Endpoint)
      endpoint.callees.each do |callee|
        callee_snippet = snippet_for(callee.path, callee.line, CALLEE_SNIPPET_RADIUS)

        context.push_callee(AIContextEntry.new(
          "callee",
          callee.name,
          source: "callee",
          description: "Direct 1-hop handler callee extracted from the endpoint body",
          path: callee.path,
          line: callee.line,
          confidence: 92,
          snippet: callee_snippet
        ))

        if sink = detect_from_patterns(callee.name, callee_snippet, SINK_PATTERNS, callee.path, callee.line, "callee")
          context.push_sink(sink)
        end

        if validator = detect_from_patterns(callee.name, callee_snippet, VALIDATOR_PATTERNS, callee.path, callee.line, "callee")
          context.push_validator(validator)
        end
      end
    end

    private def add_source_scan_entries(context : AIContext, endpoint : Endpoint)
      return if endpoint.details.code_paths.empty?

      endpoint.details.code_paths.each do |path_info|
        route_scope = route_scope_snippet_for(path_info.path, path_info.line)

        # Try each guard category independently — a route can be
        # protected by authn, authz, csrf, and rate-limit at once,
        # and the LLM should see every layer that's present so it
        # can reason about which one is missing.
        GUARD_PATTERN_GROUPS.each do |patterns|
          kind = patterns.first.kind
          next if context.guards.any? { |g| g.kind == kind }
          if guard = detect_from_patterns("", route_scope, patterns, path_info.path, path_info.line, "route_source")
            context.push_guard(guard)
          end
        end

        snippet = route_scope || snippet_for(path_info.path, path_info.line, SOURCE_SCAN_RADIUS)
        next if snippet.nil?

        # Explicit CSRF bypass is a negative signal: protection is
        # disabled here on purpose, but the reviewer should confirm
        # the justification.
        CSRF_EXEMPT_PATTERNS.each do |pattern|
          next if context.signals.any? { |s| s.kind == "csrf_exempt" }
          if entry = detect_single_pattern(pattern, "", snippet, path_info.path, path_info.line, "route_source")
            context.push_signal(entry)
          end
        end

        # Try every sink pattern, not just the first. Stops at one
        # match per `kind`, so the same SQL pattern firing twice won't
        # double-emit but a route that's both `xss` and `sql` will
        # surface both. Previously we capped the whole route at one
        # sink, which silently dropped the second / third class.
        SINK_PATTERNS.each do |pattern|
          next if context.sinks.any? { |s| s.kind == pattern.kind }
          if sink = detect_single_pattern(pattern, "", snippet, path_info.path, path_info.line, "route_source")
            context.push_sink(sink)
          end
        end

        VALIDATOR_PATTERNS.each do |pattern|
          next if context.validators.any? { |v| v.kind == pattern.kind }
          if validator = detect_single_pattern(pattern, "", snippet, path_info.path, path_info.line, "route_source")
            context.push_validator(validator)
          end
        end
      end
    end

    private def add_missing_guard_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return unless STATE_CHANGING_METHODS.includes?(endpoint.method)

      has_authn = context.guards.any? { |g| g.kind == "auth_guard" }
      has_authz = context.guards.any? { |g| g.kind == "authz_guard" }
      has_rate_limit = context.guards.any? { |g| g.kind == "rate_limit_guard" }
      path_id_param = endpoint.params.any? { |p| p.param_type == "path" && identifier_like?(p.name) }

      # Authentication is present but no authorization check is —
      # classic privilege escalation candidate. Especially noisy on
      # routes that take a path identifier (could touch another
      # user's object), but worth surfacing in either case.
      if has_authn && !has_authz && path_id_param
        context.push_signal(AIContextEntry.new(
          "authz_absence",
          endpoint.url,
          source: "heuristic",
          description: "Authenticated endpoint uses a path identifier with no authorization check detected; review for horizontal / vertical privilege escalation.",
          path: anchor.try(&.path),
          line: anchor.try(&.line),
          confidence: 44,
          snippet: route_snippet
        ))
      end

      # Rate-limit absence is informational — only emit on
      # credential-bearing endpoints where it actually matters (login,
      # password reset, OTP). General state-changing endpoints don't
      # always need rate limiting. Also accepts source-scanned
      # credential_input signals (analyzer missed the param) so
      # destructured login handlers still light up.
      credential_param = endpoint.params.any? do |p|
        PARAM_PATTERNS.find { |pattern| pattern.kind == "credential_input" }.try do |pattern|
          matches_any?(p.name, pattern.name_patterns)
        end
      end
      credential_signal = context.signals.any? { |s| s.kind == "credential_input" }
      if (credential_param || credential_signal) && !has_rate_limit
        context.push_signal(AIContextEntry.new(
          "rate_limit_absence",
          endpoint.url,
          source: "heuristic",
          description: "Credential-handling endpoint with no rate-limit / throttling layer detected; review for credential stuffing and brute-force exposure.",
          path: anchor.try(&.path),
          line: anchor.try(&.line),
          confidence: 32,
          snippet: route_snippet
        ))
      end

      # Existing authn-absence flow (preserves v1.0 behaviour).
      return unless context.guards.empty?

      if path_id_param
        context.push_signal(AIContextEntry.new(
          "idor_review",
          endpoint.url,
          source: "heuristic",
          description: "State-changing endpoint uses path identifiers without a detected guard; review object-level authorization carefully.",
          path: anchor.try(&.path),
          line: anchor.try(&.line),
          confidence: 36,
          snippet: route_snippet
        ))
      else
        context.push_signal(AIContextEntry.new(
          "guard_absence",
          endpoint.method,
          source: "heuristic",
          description: "No auth guard was detected for this state-changing endpoint. This may be real or a heuristic blind spot; review manually.",
          path: anchor.try(&.path),
          line: anchor.try(&.line),
          confidence: 28,
          snippet: route_snippet
        ))
      end
    end

    private def guard_tag?(tag : Tag) : Bool
      return true if tag.name == "auth"
      tag.tagger.downcase.ends_with?("_auth")
    end

    private def guard_name_from_tag(tag : Tag) : String
      description = tag.description
      return description.sub(/^Protected by\s+/, "") if description.starts_with?("Protected by ")
      tag.name
    end

    private def detect_from_patterns(name : String,
                                     snippet : String?,
                                     patterns : Array(PatternDefinition),
                                     path : String?,
                                     line : Int32?,
                                     source : String) : AIContextEntry?
      patterns.each do |pattern|
        if entry = detect_single_pattern(pattern, name, snippet, path, line, source)
          return entry
        end
      end

      nil
    end

    # Single-pattern variant of `detect_from_patterns`. Pulled out so
    # `add_source_scan_entries` can iterate every sink/validator
    # pattern independently (one match per kind), where the legacy
    # behaviour stopped at the first match across the whole list.
    private def detect_single_pattern(pattern : PatternDefinition,
                                      name : String,
                                      snippet : String?,
                                      path : String?,
                                      line : Int32?,
                                      source : String) : AIContextEntry?
      return nil if suppress_pattern_detection?(pattern.kind, name, snippet)

      name_match = name_match_text(name, pattern.name_patterns)
      snippet_match = snippet_match_text(snippet, pattern.source_patterns)
      return nil unless name_match || snippet_match
      return nil if source == "callee" && name_match.nil?

      evidence_name = name_match || snippet_match || pattern.kind
      AIContextEntry.new(
        pattern.kind,
        evidence_name,
        source: source,
        description: pattern.description,
        path: path,
        line: line,
        confidence: source == "route_source" ? pattern.confidence - 12 : pattern.confidence,
        snippet: snippet
      )
    end

    private def suppress_pattern_detection?(kind : String, name : String, snippet : String?) : Bool
      case kind
      when "sql"
        return true if name.matches?(/\b(URL\.Query|QueryParam|request\.query|req\.query|query_params|searchParams)\b/i)
        return true if snippet && snippet.matches?(/\b(URL\.Query\(\)\.Get|QueryParam\(|request\.query\.|req\.query\.|searchParams\.get)\b/i)
      when "template_render"
        return false unless snippet
        return true if snippet.matches?(/\brender\s+(json|plain|xml|body|status):/i)
        return true if snippet.matches?(/\brespond(Text|Bytes|File|Json|Redirect)\b/)
      when "outbound_http"
        return true if name.starts_with?("request.")
        return true if name == "request"
      when "crypto_weak"
        # Weak hash primitives are common for non-security uses (cache
        # keys, ETags, file fingerprints). Only flag when the snippet
        # also mentions a security-relevant identifier — keeps the
        # signal noise down for codebases that hash file paths or
        # serialize cache state.
        return true unless snippet
        return false if snippet.matches?(/\b(password|passwd|secret|token|session|sign(ature)?|nonce|otp|cred(ential)?|jwt|hmac|salt|api[_-]?key)\b/i)
        # AES/ECB and RC4 are weak regardless of context — keep the
        # snippet match alone good enough for those.
        return !snippet.matches?(/\bAES\/ECB\b|\bMode::ECB\b|\bRC4\b|\b['"]DES['"]?\b/)
      when "code_eval"
        return false unless snippet
        # `compile(..., 'exec')` already has an explicit 'exec' marker
        # in our regex; bare `compile()` from JSON/template tooling
        # must not collide. Keep the targeted patterns above and skip
        # generic compile() calls that didn't carry the 'exec' arg.
        return true if name == "compile"
      when "mass_assignment"
        return false unless snippet
        # If the snippet shows `.permit(` or `parse(`/`validate(` near
        # the suspect call, the developer already gated it. Skip the
        # warning in that case.
        return snippet.matches?(/\.permit\s*\(/) || snippet.matches?(/\.(parse|validate)\s*\(/i)
      end

      false
    end

    private def name_match_text(name : String, patterns : Array(Regex)) : String?
      return if name.empty?

      patterns.each do |pattern|
        if match = name.match(pattern)
          return normalize_label(match[0])
        end
      end

      nil
    end

    private def snippet_match_text(snippet : String?, patterns : Array(Regex)) : String?
      return unless snippet

      patterns.each do |pattern|
        if match = snippet.match(pattern)
          return normalize_label(match[0])
        end
      end

      nil
    end

    private def matches_any?(name : String, patterns : Array(Regex)) : Bool
      patterns.any? { |pattern| name.matches?(pattern) }
    end

    private def identifier_like?(name : String) : Bool
      return true if matches_any?(name, PARAM_PATTERNS.find! { |pattern| pattern.kind == "identifier_input" }.name_patterns)
      return true if identifier_suffix_like?(name)

      false
    end

    private def header_identifier_like?(name : String) : Bool
      normalized = name.downcase
      return true if normalized.matches?(/\b[a-z0-9_-]*id\b/)
      return true if normalized.matches?(/\b(client|account|order|profile|project|merchant|store|user)[_-]?id\b/)

      false
    end

    private def identifier_suffix_like?(name : String) : Bool
      return true if name == "id"
      return true if name.matches?(/[_-]id$/i)
      return true if name.matches?(/[a-z0-9]Id$/)
      return true if name.matches?(/[a-z0-9]ID$/)

      false
    end

    private def normalize_label(text : String) : String
      text.gsub(/\s+/, " ").strip[0, Math.min(text.gsub(/\s+/, " ").strip.size, 64)]
    end

    private def snippet_for(path : String?, line : Int32?, radius : Int32) : String?
      return unless path && line

      lines = read_lines(path)
      return if line < 1 || line > lines.size

      start_idx = Math.max(line - radius - 1, 0)
      end_idx = Math.min(line + radius - 1, lines.size - 1)
      selected = [] of String

      (start_idx..end_idx).each do |idx|
        selected << "#{idx + 1}: #{lines[idx].strip}"
      end

      snippet = selected.join(" | ").gsub(/\s+/, " ").strip
      return if snippet.empty?
      snippet.size > MAX_SNIPPET_CHARS ? snippet[0, MAX_SNIPPET_CHARS] : snippet
    end

    private def route_scope_snippet_for(path : String?, line : Int32?) : String?
      return unless path && line

      lines = read_lines(path)
      return if line < 1 || line > lines.size

      start_idx = line - 1
      selected = [] of String
      brace_depth = 0
      paren_balance = 0
      # Block style starts as `nil` and locks in to one of:
      #   :brace   — JS / Go / Java / Rust / C-family `{ ... }`
      #   :ruby    — Ruby `def name` (ends on a line with `end` at
      #              the same indent as `def`)
      #   :python  — Python `def name():` / `class …:` (ends when a
      #              non-blank line returns to ≤ the def's indent)
      block_style : Symbol? = nil
      # Indent of the `def` / `class` that triggered :python / :ruby
      # mode. We use it to stop the capture when control returns to
      # that column (= the next top-level statement / next decorator).
      def_indent : Int32? = nil

      start_idx.upto(Math.min(start_idx + MAX_ROUTE_SCOPE_LINES - 1, lines.size - 1)) do |idx|
        raw_line = lines[idx]
        line_indent = raw_line.size - raw_line.lstrip.size

        # Indent-based end-of-block check for :python / :ruby. Runs
        # BEFORE we append the line, so we don't bleed into the next
        # function / decorator (the bug behind the django `/public/`
        # false-positive — the next function's `@login_required`
        # decorator was getting captured into the previous handler's
        # scope).
        if (def_idx = def_indent) && (style = block_style)
          if (style == :python || style == :ruby) &&
             !raw_line.strip.empty? && line_indent <= def_idx
            # `end` on a line at def-column belongs to the def — keep
            # it. Anything else at that column is the *next* statement.
            stripped_check = raw_line.strip
            if !(style == :ruby && stripped_check == "end")
              break
            end
          end
        end

        selected << "#{idx + 1}: #{raw_line.strip}"

        sanitized = raw_line.gsub(/(['"]).*?\1/, "\"\"")
        opens = sanitized.count('{')
        closes = sanitized.count('}')
        brace_depth += opens - closes
        paren_balance += sanitized.count('(') - sanitized.count(')')

        stripped = sanitized.strip
        # Decorator / annotation lines (`@app.route(...)`, `@PostMapping(...)`,
        # `@PreAuthorize(...)`) come *before* the actual route handler.
        # Their trailing `)` is not end-of-statement — the handler is on
        # the next line(s).
        is_decorator = stripped.starts_with?("@")

        # Lock in a block style on the first line that opens one. Once
        # locked, later lines don't change the kind.
        if block_style.nil?
          if opens > 0 || sanitized.matches?(/\bdo\b/)
            block_style = :brace
          elsif !is_decorator && stripped.ends_with?(":")
            block_style = :python
            def_indent = line_indent
          elsif !is_decorator && (stripped.matches?(/\b(def|class)\s+\w+/) || stripped.matches?(/\bfunction\s+\w+/))
            block_style = :ruby
            def_indent = line_indent
          end
        end

        case block_style
        when :brace
          # JS-style: capture until braces close back to zero.
          break if brace_depth <= 0
        when :python
          # Indent guard runs at the top of the next iteration; no
          # per-line break needed here.
        when :ruby
          # Stop after the matching `end` at the def's indent.
          if def_indent == line_indent && stripped == "end"
            break
          end
        else
          statement_done = !is_decorator && (stripped.ends_with?(";") || stripped.ends_with?(")") || stripped.ends_with?(" do"))
          break if statement_done && paren_balance <= 0
        end
      end

      snippet = selected.join(" | ").gsub(/\s+/, " ").strip
      return if snippet.empty?
      snippet.size > MAX_SNIPPET_CHARS ? snippet[0, MAX_SNIPPET_CHARS] : snippet
    end

    private def read_lines(path : String) : Array(String)
      if cached = @file_cache[path]?
        return cached
      end

      lines = File.read(path, encoding: "utf-8", invalid: :skip).split("\n")
      @file_cache[path] = lines
      lines
    rescue
      [] of String
    end
  end
end
