require "../models/endpoint"
require "./patterns"
require "./pattern_matcher"
require "./source_reader"

module NoirAIContext
  # Builds an AIContext for each endpoint by running every populate
  # step (route / technology / method / param / tag / callee / source
  # scan / guard-absence / combination signals) over the endpoint and
  # its source. Pattern detection is delegated to `PatternMatcher` and
  # source/snippet reading to a per-run `SourceReader` (file cache).
  class Builder
    ROUTE_SNIPPET_RADIUS  = 2
    SOURCE_SCAN_RADIUS    = 6
    CALLEE_SNIPPET_RADIUS = 1

    STATE_CHANGING_METHODS = Set{"POST", "PUT", "PATCH", "DELETE"}
    BODY_LIKE_PARAM_TYPES  = Set{"json", "form"}

    @reader : SourceReader

    def initialize
      @reader = SourceReader.new
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
      route_snippet = @reader.snippet_for(anchor.try(&.path), anchor.try(&.line), ROUTE_SNIPPET_RADIUS)

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
      add_ssrf_signal(context, anchor, route_snippet)
      add_path_traversal_signal(context, anchor, route_snippet)
      add_sensitive_response_signal(context, endpoint, anchor, route_snippet)
      add_unsafe_method_signal(context, endpoint, anchor, route_snippet)
      add_log_injection_signal(context, endpoint, anchor, route_snippet)
      add_priority_review_signal(context, endpoint, anchor, route_snippet)
    end

    # SSRF candidate: handler has an outbound_http sink AND a URL-
    # like input (redirect_input param covers url/uri/redirect/
    # return/next/dest/callback — all the names that typically
    # carry attacker-controlled URLs into server-side fetches).
    private def add_ssrf_signal(context : AIContext, anchor : PathInfo?, route_snippet : String?)
      return unless context.sinks.any? { |s| s.kind == "outbound_http" }
      return unless context.signals.any? { |s| s.kind == "redirect_input" }
      return if context.signals.any? { |s| s.kind == "ssrf" }

      outbound = context.sinks.find! { |s| s.kind == "outbound_http" }
      context.push_signal(AIContextEntry.new(
        "ssrf",
        outbound.name,
        source: "heuristic",
        description: "Handler makes an outbound HTTP request alongside a URL-like input — classic SSRF signature. Review whether the destination is validated against an allowlist of hosts/schemes.",
        path: anchor.try(&.path) || outbound.path,
        line: anchor.try(&.line) || outbound.line,
        confidence: 72,
        snippet: route_snippet || outbound.snippet
      ))
    end

    # Path-traversal candidate: handler has a *code-derived* file_io
    # sink AND a file-like input. The "code-derived" qualifier is
    # what keeps this honest: the FileUpload tagger pushes a
    # `file_io` sink to flag the endpoint as a file-handling route,
    # but receiving a multipart upload doesn't itself imply that
    # the file's PATH is attacker-controlled. The traversal pattern
    # specifically wants `File.read(filename_from_user)` style sinks,
    # not "endpoint accepts file content as bytes".
    private def add_path_traversal_signal(context : AIContext, anchor : PathInfo?, route_snippet : String?)
      code_derived_file_sink = context.sinks.find do |s|
        s.kind == "file_io" && s.source != "FileUpload"
      end
      return unless code_derived_file_sink
      return unless context.signals.any? { |s| s.kind == "file_input" }
      return if context.signals.any? { |s| s.kind == "path_traversal" }

      context.push_signal(AIContextEntry.new(
        "path_traversal",
        code_derived_file_sink.name,
        source: "heuristic",
        description: "Handler performs file I/O alongside a path/filename-like input. Review for `../` traversal and ensure the resolved path stays inside an allow-listed root.",
        path: anchor.try(&.path) || code_derived_file_sink.path,
        line: anchor.try(&.line) || code_derived_file_sink.line,
        confidence: 68,
        snippet: route_snippet || code_derived_file_sink.snippet
      ))
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
      "jwt_unsafe",
      "cors_open",
      "open_redirect",
      "ssrf",
      "path_traversal",
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
      # `csrf_exempt` / `jwt_unsafe` / `cors_open` / `open_redirect`
      # are individually loud enough to bump the bucket even when
      # other signals are quiet — explicit protection-bypass /
      # well-known misconfiguration classes that don't need a
      # second supporting signal to be worth surfacing.
      #
      # csrf_exempt is method-gated: CSRF only protects state-
      # changing methods, so an @csrf_exempt decorator on a GET /
      # HEAD endpoint (often the GET-side of a `methods=['GET',
      # 'POST']` Flask split) has no security impact. Don't let it
      # bump priority on those routes.
      method_safe = SAFE_METHODS.includes?(endpoint.method)
      sharp_signal = context.signals.any? do |s|
        case s.kind
        when "csrf_exempt"
          !method_safe
        when "open_redirect", "jwt_unsafe", "cors_open"
          true
        else
          false
        end
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

    # Each verb may be followed by additional word chars
    # (`destroy_all`, `createMany`, `deleteOne`, `updateUser`), so we
    # don't anchor with a trailing `\b` — that would miss those
    # suffixed forms because `_` and word continuation count as the
    # same word in regex.
    MUTATING_CALLEE_PATTERN = /\b(create|destroy|delete|update|save|insert|remove|drop|truncate|persist|flush|commit|rollback|set_)\w*/i

    # Suppression for unsafe_method: route handlers that branch on
    # `request.method` (Flask / Django) or `req.method` (Express,
    # Node, Go's r.Method, Java's request.getMethod()) typically
    # register a single route under multiple methods. Analyzers
    # split that into one endpoint per method but share the
    # callees list. The mutating callee in the GET endpoint is
    # often the POST branch's call, not actually reachable via GET.
    METHOD_DISPATCH_PATTERN = /(?:request\.method\s*==|req\.method\s*==|r\.Method\s*==|request\.getMethod\(\)\s*\.equals|\.match\(\s*['"](?:GET|POST|PUT|PATCH|DELETE)['"])/i

    private def add_unsafe_method_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return unless SAFE_METHODS.includes?(endpoint.method)
      return if context.signals.any? { |s| s.kind == "unsafe_method" }

      mutating = endpoint.callees.find(&.name.matches?(MUTATING_CALLEE_PATTERN))
      return unless mutating

      # If the handler dispatches on HTTP method internally, we
      # can't tell from the callee list alone which branch the
      # mutation lives in — better to skip the signal than fire it
      # falsely. The augmentor would also emit it on the genuinely
      # state-changing endpoint (POST/PUT/DELETE) for the same
      # route, where it doesn't apply (state-change is expected).
      if route_snippet && route_snippet.matches?(METHOD_DISPATCH_PATTERN)
        return
      end
      endpoint.details.code_paths.each do |path_info|
        scope = @reader.route_scope_snippet_for(path_info.path, path_info.line)
        if scope && scope.matches?(METHOD_DISPATCH_PATTERN)
          return
        end
      end

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
        scope = @reader.route_scope_snippet_for(path_info.path, path_info.line)
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

      redirect_sink = context.sinks.find! { |s| s.kind == "redirect" }
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
    RESPONSE_EMITTER_PATTERN   = /\b(jsonify|res\.json|json_response|JsonResponse|render\s+json:|to_json|respond_with)\b/i
    CREDENTIAL_KEY_IN_RESPONSE = /[^"'\w](password|passwd|token|secret|api[_-]?key|session_id|access_token|refresh_token|private_key)\s*:/i

    private def add_sensitive_response_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return if context.signals.any? { |s| s.kind == "sensitive_response" }
      return if endpoint.details.code_paths.empty?

      endpoint.details.code_paths.each do |path_info|
        scope = @reader.route_scope_snippet_for(path_info.path, path_info.line)
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
      # Go net/http and common framework helpers: `r.FormValue("password")`,
      # `c.PostForm("token")`, `ctx.FormValue("secret")`, …
      /\b(?:r|req|request)\.(?:FormValue|PostFormValue)\s*\(\s*['"](password|passwd|token|secret|api[_-]?key|jwt|bearer)['"]/i,
      /\b(?:c|ctx|context)\.(?:PostForm|DefaultPostForm|FormValue|QueryParam)\s*\(\s*['"](password|passwd|token|secret|api[_-]?key|jwt|bearer)['"]/i,
      # C# minimal APIs / controllers: `context.Request.Form["password"]`,
      # `Request.Headers["Authorization"]`, …
      /\b(?:context\.Request|HttpContext\.Request|Request)\.(?:Form|Query|Headers|Cookies)\s*\[\s*['"](password|passwd|token|secret|api[_-]?key|authorization|jwt|bearer)['"]/i,
      # Java/Kotlin field access on a DTO marked @RequestBody: `c.password`
      # is too generic alone; require the credential noun directly.
      /\b(password|passwd|token|secret|api[_-]?key|jwt|bearer)\s*=\s*req\./i,
    ]

    private def add_credential_from_source_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?)
      return if context.signals.any? { |s| s.kind == "credential_input" }
      return if endpoint.details.code_paths.empty?

      endpoint.details.code_paths.each do |path_info|
        snippet = @reader.route_scope_snippet_for(path_info.path, path_info.line)
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
          next unless PatternMatcher.matches_any?(param.name, pattern.name_patterns)
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
        callee_snippet = @reader.snippet_for(callee.path, callee.line, CALLEE_SNIPPET_RADIUS)

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

        if sink = PatternMatcher.detect_from_patterns(callee.name, callee_snippet, SINK_PATTERNS, callee.path, callee.line, "callee")
          context.push_sink(sink)
        end

        if validator = PatternMatcher.detect_from_patterns(callee.name, callee_snippet, VALIDATOR_PATTERNS, callee.path, callee.line, "callee")
          context.push_validator(validator)
        end
      end
    end

    private def add_source_scan_entries(context : AIContext, endpoint : Endpoint)
      return if endpoint.details.code_paths.empty?

      endpoint.details.code_paths.each do |path_info|
        route_scope = @reader.route_scope_snippet_for(path_info.path, path_info.line)

        # Try each guard category independently — a route can be
        # protected by authn, authz, csrf, and rate-limit at once,
        # and the LLM should see every layer that's present so it
        # can reason about which one is missing.
        GUARD_PATTERN_GROUPS.each do |patterns|
          kind = patterns.first.kind
          next if context.guards.any? { |g| g.kind == kind }
          if guard = PatternMatcher.detect_from_patterns("", route_scope, patterns, path_info.path, path_info.line, "route_source")
            context.push_guard(guard)
          end
        end

        snippet = route_scope || @reader.snippet_for(path_info.path, path_info.line, SOURCE_SCAN_RADIUS)
        next if snippet.nil?

        # Explicit CSRF bypass is a negative signal. CSRF only
        # protects state-changing methods, so suppress it on safe
        # endpoints split out from multi-method handlers.
        unless SAFE_METHODS.includes?(endpoint.method)
          CSRF_EXEMPT_PATTERNS.each do |pattern|
            next if context.signals.any? { |s| s.kind == "csrf_exempt" }
            if entry = PatternMatcher.detect_single_pattern(pattern, "", snippet, path_info.path, path_info.line, "route_source")
              context.push_signal(entry)
            end
          end
        end

        # JWT verification bypass — same family as csrf_exempt.
        JWT_UNSAFE_PATTERNS.each do |pattern|
          next if context.signals.any? { |s| s.kind == "jwt_unsafe" }
          if entry = PatternMatcher.detect_single_pattern(pattern, "", snippet, path_info.path, path_info.line, "route_source")
            context.push_signal(entry)
          end
        end

        # CORS open-with-credentials: needs BOTH patterns in the
        # snippet to be a real misconfiguration. A wildcard origin
        # without credentials is fine (public APIs do this); a
        # credentials-true config without a wildcard origin is fine
        # (just sets a sensible CORS). It's the combination that
        # bites.
        unless context.signals.any? { |s| s.kind == "cors_open" }
          if snippet.matches?(CORS_WILDCARD_PATTERN) && snippet.matches?(CORS_CREDENTIALS_PATTERN)
            context.push_signal(AIContextEntry.new(
              "cors_open",
              "origin=* + credentials=true",
              source: "route_source",
              description: "CORS configured with wildcard origin AND credentials — browsers reject this combination at the spec level, so either the config is broken or the developer is intentionally weakening cross-origin policy. Either way, review.",
              path: path_info.path,
              line: path_info.line,
              confidence: 84,
              snippet: snippet
            ))
          end
        end

        # Try every sink pattern, not just the first. Stops at one
        # match per `kind`, so the same SQL pattern firing twice won't
        # double-emit but a route that's both `xss` and `sql` will
        # surface both. Previously we capped the whole route at one
        # sink, which silently dropped the second / third class.
        SINK_PATTERNS.each do |pattern|
          next if context.sinks.any? { |s| s.kind == pattern.kind }
          if sink = PatternMatcher.detect_single_pattern(pattern, "", snippet, path_info.path, path_info.line, "route_source")
            context.push_sink(sink)
          end
        end

        VALIDATOR_PATTERNS.each do |pattern|
          next if context.validators.any? { |v| v.kind == pattern.kind }
          if validator = PatternMatcher.detect_single_pattern(pattern, "", snippet, path_info.path, path_info.line, "route_source")
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
          PatternMatcher.matches_any?(p.name, pattern.name_patterns)
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

    private def identifier_like?(name : String) : Bool
      return true if PatternMatcher.matches_any?(name, PARAM_PATTERNS.find! { |pattern| pattern.kind == "identifier_input" }.name_patterns)
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
  end
end
