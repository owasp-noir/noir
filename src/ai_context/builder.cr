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
    MOBILE_SOURCE_EXTS     = Set{".swift", ".m", ".mm", ".kt", ".java"}

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
      add_mobile_deep_link_source(context, endpoint, anchor, route_snippet)
      add_tag_entries(context, endpoint, anchor, route_snippet)
      add_graphql_resolver_signal(context, endpoint)
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
      add_object_lookup_signal(context, endpoint, anchor, route_snippet)
      add_object_write_signal(context, endpoint, anchor, route_snippet)
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
      "server_secret_source",
      "unsafe_method",
      "log_injection",
      "deep_link_input",
    }

    # Categories whose mere presence is a security-review signal —
    # used alongside concrete signals to compute the overall
    # priority bucket.
    PRIORITY_SCORING_SINK_BLACKLIST = Set{
      "sql", "data_store_query", "command_exec", "code_eval",
      "deserialization", "template_injection", "xss",
      "mass_assignment", "crypto_weak", "webview_load", "intent_redirect",
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
      heavy_sink_kinds = Set(String).new
      context.sinks.each do |sink|
        next if priority_scoring_sink_mitigated?(context, sink.kind)
        heavy_sink_kinds << sink.kind if PRIORITY_SCORING_SINK_BLACKLIST.includes?(sink.kind)
      end
      heavy_sinks = heavy_sink_kinds.size

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
                  description: "Medium-priority review candidate — multiple review signals co-occur on this endpoint."}
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

    private def priority_scoring_sink_mitigated?(context : AIContext, sink_kind : String) : Bool
      return false unless sink_kind.in?("sql", "data_store_query")

      context.validators.any? { |validator| validator.kind == "query_parameter_binding" }
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
      return if endpoint.mobile?
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
        next unless scope.matches?(LOG_INPUT_OR_CRED_PATTERN) || logs_endpoint_param?(endpoint, scope)

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

    private def logs_endpoint_param?(endpoint : Endpoint, scope : String) : Bool
      endpoint.params.any? do |param|
        next false if param.name.starts_with?("graphql_")

        escaped = Regex.escape(param.name)
        scope.matches?(Regex.new("\\$(?:\\{#{escaped}\\}|#{escaped}\\b)"))
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
    RESPONSE_EMITTER_PATTERN         = /\b(jsonify|res\.json|json_response|JsonResponse|render\s+json:|to_json|respond_with)\b/i
    CREDENTIAL_KEY_IN_RESPONSE       = /[^"'\w](password|passwd|token|secret|api[_-]?key|session_id|access_token|refresh_token|private_key)\s*:/i
    KOTLIN_CREDENTIAL_RETURN_PATTERN = /\bfun\s+\w+[^{|;]*=\s*(?:this\.)?(password|passwd|token|secret|api[_-]?key|session_?id|access_?token|refresh_?token|private_?key)\b/i

    private def add_sensitive_response_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return if context.signals.any? { |s| s.kind == "sensitive_response" }
      return if endpoint.details.code_paths.empty?

      endpoint.details.code_paths.each do |path_info|
        scope = @reader.route_scope_snippet_for(path_info.path, path_info.line)
        next unless scope

        if match = scope.match(KOTLIN_CREDENTIAL_RETURN_PATTERN)
          field = match[1]? || "credential"
          context.push_signal(AIContextEntry.new(
            "sensitive_response",
            field.downcase,
            source: "route_source",
            description: "Handler directly returns a credential-bearing value; review whether the response exposes server-side secrets or tokens.",
            path: path_info.path,
            line: path_info.line,
            confidence: 70,
            snippet: scope
          ))
          add_spring_value_secret_source_signal(context, path_info.path, field)
          return
        end

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

    SPRING_VALUE_ANNOTATION_PATTERN = /@Value\s*\(([^)]*)\)/
    SPRING_CONFIG_KEY_PATTERN       = /\$\{([^}:]+)/
    SPRING_SECRET_NAME_PATTERN      = /\b(pass(word)?|secret|token|api[_.-]?key|credential|jwt|private[_.-]?key)\b/i

    private def add_spring_value_secret_source_signal(context : AIContext, path : String?, field : String)
      return if context.signals.any? { |s| s.kind == "server_secret_source" } &&
                context.sources.any? { |s| s.kind == "server_secret_source" }

      lines = @reader.lines_for(path)
      return if lines.empty?

      # Compile the declaration pattern once for this field instead of per
      # `@Value` line; `field` is a fixed credential word but escape it anyway.
      field_declaration_pattern = Regex.new("\\b(?:[A-Za-z_][A-Za-z0-9_<>?]*\\s+)*(?:var|val)\\s+#{Regex.escape(field)}\\b")

      lines.each_with_index do |line, idx|
        next unless line.includes?("@Value")

        window_lines = [] of String
        idx.upto(Math.min(idx + 3, lines.size - 1)) do |line_idx|
          window_lines << lines[line_idx].strip
        end
        window = window_lines.join(" ")
        next unless window.matches?(field_declaration_pattern)

        value_expr = spring_value_expression(window)
        next unless spring_secret_source?(field, value_expr)

        entry = AIContextEntry.new(
          "server_secret_source",
          spring_secret_source_name(field, value_expr),
          source: "route_source",
          description: "Handler returns a credential-like value injected from Spring @Value; review whether server-side configuration or environment secrets are exposed.",
          path: path,
          line: idx + 1,
          confidence: 74,
          snippet: @reader.snippet_for(path, idx + 1, 1)
        )
        context.push_signal(entry)
        context.push_source(entry)
        return
      end
    end

    private def spring_value_expression(window : String) : String?
      if match = window.match(SPRING_VALUE_ANNOTATION_PATTERN)
        return match[1]?
      end

      nil
    end

    private def spring_secret_source?(field : String, value_expr : String?) : Bool
      return true if field.matches?(SPRING_SECRET_NAME_PATTERN)

      value_expr.try(&.matches?(SPRING_SECRET_NAME_PATTERN)) || false
    end

    private def spring_secret_source_name(field : String, value_expr : String?) : String
      if value_expr && (match = value_expr.match(SPRING_CONFIG_KEY_PATTERN))
        "Spring @Value #{match[1]} -> #{field}"
      else
        "Spring @Value -> #{field}"
      end
    end

    OBJECT_LOOKUP_PRIMARY_CALLEE_PATTERN  = /(?:^|\.)(?:findById|findOne|getOne|existsById|find\w*ById|find\w*By\w*Id|(?:find|count|exists)By\w*Id)\b/i
    OBJECT_LOOKUP_FALLBACK_CALLEE_PATTERN = /(?:^|\.)(?:deleteById|removeById|get\w*ById|retrieve\w*)\b/i

    private def add_object_lookup_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return if context.signals.any? { |s| s.kind == "object_lookup" }
      return unless object_lookup_identifier_param?(endpoint)

      lookup = object_lookup_callee(endpoint)
      return unless lookup

      context.push_signal(AIContextEntry.new(
        "object_lookup",
        lookup.name,
        source: "heuristic",
        description: "Identifier input flows into an object lookup or object access callee; review object-level authorization and not-found behavior around this access.",
        path: lookup.path || anchor.try(&.path),
        line: lookup.line || anchor.try(&.line),
        confidence: 66,
        snippet: route_snippet
      ))
    end

    private def object_lookup_callee(endpoint : Endpoint) : Callee?
      primary = endpoint.callees.select { |callee| callee.name.matches?(OBJECT_LOOKUP_PRIMARY_CALLEE_PATTERN) }
      primary.find { |callee| callee.name.matches?(/\b\w+(?:Repository|Repo|Dao)\./) } ||
        primary.first? ||
        endpoint.callees.find { |callee| callee.name.matches?(OBJECT_LOOKUP_FALLBACK_CALLEE_PATTERN) }
    end

    private def object_lookup_identifier_param?(endpoint : Endpoint) : Bool
      return true if endpoint.params.any? { |p| p.param_type == "path" && identifier_like?(p.name) }
      return true if endpoint.params.any? { |p| p.param_type == "query" && identifier_like?(p.name) }
      return true if STATE_CHANGING_METHODS.includes?(endpoint.method) &&
                     endpoint.params.any? { |p| BODY_LIKE_PARAM_TYPES.includes?(p.param_type) && identifier_like?(p.name) }
      return true if graphql_field_endpoint?(endpoint)
      return false unless graphql_endpoint?(endpoint)

      endpoint.params.any? do |param|
        param.param_type == "json" &&
          identifier_like?(param.name) &&
          !param.name.starts_with?("graphql_")
      end
    end

    private def add_object_write_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return if context.signals.any? { |s| s.kind == "object_write" }
      return if context.signals.any? { |s| s.kind == "object_lookup" }
      return unless STATE_CHANGING_METHODS.includes?(endpoint.method)
      return unless endpoint.params.any? { |p| p.param_type == "path" && identifier_like?(p.name) }

      mutating = endpoint.callees.find(&.name.matches?(MUTATING_CALLEE_PATTERN))
      return unless mutating

      context.push_signal(AIContextEntry.new(
        "object_write",
        mutating.name,
        source: "heuristic",
        description: "Path identifier participates in an object-scoped write without a detected lookup callee; review ownership and parent-child authorization around this mutation.",
        path: mutating.path || anchor.try(&.path),
        line: mutating.line || anchor.try(&.line),
        confidence: 52,
        snippet: route_snippet
      ))
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
      add_spring_graphql_resolver_technology_signal(context, endpoint, anchor)
    end

    private def add_spring_graphql_resolver_technology_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?)
      return if endpoint.details.technology == "kotlin_spring"
      return unless endpoint.tags.any? { |tag| tag.tagger == "kotlin_spring_graphql_analyzer" }
      return if context.signals.any? { |signal| signal.kind == "technology" && signal.name == "kotlin_spring" }

      resolver_anchor = endpoint.details.code_paths.find(&.path.ends_with?(".kt")) || anchor
      snippet = @reader.snippet_for(resolver_anchor.try(&.path), resolver_anchor.try(&.line), ROUTE_SNIPPET_RADIUS)
      context.push_signal(AIContextEntry.new(
        "technology",
        "kotlin_spring",
        source: "resolver",
        description: "Spring GraphQL resolver implementation was matched to this endpoint.",
        path: resolver_anchor.try(&.path),
        line: resolver_anchor.try(&.line),
        confidence: 90,
        snippet: snippet
      ))
    end

    private def add_method_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return unless STATE_CHANGING_METHODS.includes?(endpoint.method)
      return if graphql_read_endpoint?(endpoint)
      return if read_only_post_endpoint?(endpoint)

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

    private def add_mobile_deep_link_source(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return unless endpoint.mobile?

      source_anchor = mobile_handler_anchor(endpoint) || anchor
      snippet = if source_anchor == anchor
                  route_snippet
                else
                  @reader.snippet_for(source_anchor.try(&.path), source_anchor.try(&.line), ROUTE_SNIPPET_RADIUS)
                end
      source_name = mobile_deep_link_source_name(endpoint)

      context.push_source(AIContextEntry.new(
        "request_input",
        source_name,
        source: "mobile_deep_link",
        description: mobile_deep_link_source_description(endpoint),
        path: source_anchor.try(&.path),
        line: source_anchor.try(&.line),
        confidence: 86,
        snippet: snippet
      ))

      signal_description = if endpoint.protocol == "android-provider"
                             "Exported ContentProvider entry point receives a content:// URI and selection from another app; review downstream SQL, file, and path handling."
                           else
                             "Mobile deep-link entry point receives URL/userActivity data from outside the app; review downstream parsing, routing, and WebView/intent usage."
                           end
      context.push_signal(AIContextEntry.new(
        "deep_link_input",
        source_name,
        source: "mobile_deep_link",
        description: signal_description,
        path: source_anchor.try(&.path),
        line: source_anchor.try(&.line),
        confidence: 74,
        snippet: snippet
      ))
    end

    private def mobile_handler_anchor(endpoint : Endpoint) : PathInfo?
      endpoint.details.code_paths.find do |path_info|
        MOBILE_SOURCE_EXTS.includes?(File.extname(path_info.path))
      end
    end

    private def mobile_deep_link_source_name(endpoint : Endpoint) : String
      case endpoint.protocol
      when "universal-link"
        "deep_link.universal_link"
      when "android-intent"
        "deep_link.android_intent"
      when "android-provider"
        "ipc.content_provider"
      else
        "deep_link.mobile_scheme"
      end
    end

    private def mobile_deep_link_source_description(endpoint : Endpoint) : String
      case endpoint.protocol
      when "universal-link"
        "Universal Link URL supplied by the operating system from an external HTTPS navigation."
      when "android-intent"
        "Android intent deep-link data supplied by another app or browser."
      when "android-provider"
        "ContentProvider query/openFile reachable from another app via content:// URI; review the URI, selection, and selectionArgs for SQL injection and path traversal."
      else
        "Custom URL-scheme deep-link supplied by another app or browser."
      end
    end

    private def add_param_signals(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      endpoint.params.each do |param|
        add_param_source(context, param, anchor, route_snippet)
        add_path_param_signal(context, param, anchor, route_snippet)

        PARAM_PATTERNS.each do |pattern|
          next unless param_matches_pattern?(param, pattern)
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
          next if skip_param_tag_signal?(endpoint, param, tag)

          context.push_signal(AIContextEntry.new(
            tag.name,
            "#{param.param_type}.#{param.name}",
            source: "param_tagger:#{tag.tagger}",
            description: param_tag_description(tag),
            path: anchor.try(&.path),
            line: anchor.try(&.line),
            confidence: 58,
            snippet: route_snippet
          ))
        end
      end
    end

    private def add_param_source(context : AIContext, param : Param, anchor : PathInfo?, route_snippet : String?)
      if graphql_source = graphql_field_source_name(param)
        context.push_source(AIContextEntry.new(
          "request_input",
          graphql_source,
          source: "param",
          description: "GraphQL field selected by the caller; resolver executes while resolving the parent object.",
          path: anchor.try(&.path),
          line: anchor.try(&.line),
          confidence: 78,
          snippet: route_snippet
        ))
        return
      end

      return if param.name.starts_with?("graphql_")

      context.push_source(AIContextEntry.new(
        "request_input",
        "#{param.param_type}.#{param.name}",
        source: "param",
        description: param_source_description(param),
        path: anchor.try(&.path),
        line: anchor.try(&.line),
        confidence: param_source_confidence(param),
        snippet: route_snippet
      ))
    end

    private def graphql_field_source_name(param : Param) : String?
      return unless param.name.starts_with?("graphql_field_")

      field_name = param.value.strip.gsub(/^field\s+/, "")
      field_name = param.name.gsub(/^graphql_field_/, "") if field_name.empty?
      field_name.empty? ? nil : "graphql.field.#{field_name}"
    end

    private def param_source_description(param : Param) : String
      case param.param_type
      when "path"
        "Route path parameter supplied by the caller."
      when "query"
        "Query-string parameter supplied by the caller."
      when "header"
        "HTTP header supplied by the caller."
      when "json", "form"
        "Request body field supplied by the caller."
      else
        "Request parameter supplied by the caller."
      end
    end

    private def param_source_confidence(param : Param) : Int32
      case param.param_type
      when "path"
        88
      when "query", "header"
        84
      when "json", "form"
        82
      else
        76
      end
    end

    private def param_matches_pattern?(param : Param, pattern : PatternDefinition) : Bool
      return true if PatternMatcher.matches_any?(param.name, pattern.name_patterns)
      return false if pattern.kind == "identifier_input" && param.name.starts_with?("graphql_")
      return true if pattern.kind == "identifier_input" && identifier_like?(param.name)

      false
    end

    private def param_tag_description(tag : Tag) : String
      return tag.description if tag.tagger == "kotlin_spring_validation_analyzer"

      "#{tag.description} Matched by parameter-name heuristic."
    end

    private def skip_param_signal?(endpoint : Endpoint, param : Param, pattern : PatternDefinition) : Bool
      return true if pattern.kind == "file_input" && param.param_type == "header"
      return false unless pattern.kind == "identifier_input"
      return !header_identifier_like?(param.name) if param.param_type == "header"
      return true if safe_kotlin_query_identifier_without_lookup?(endpoint, param)
      return false unless BODY_LIKE_PARAM_TYPES.includes?(param.param_type)
      return true if param.name == "id"

      body_identifier_overwritten_from_path?(endpoint, param)
    end

    private def safe_kotlin_query_identifier_without_lookup?(endpoint : Endpoint, param : Param) : Bool
      return false unless endpoint.details.technology == "kotlin_spring"
      return false unless SAFE_METHODS.includes?(endpoint.method)
      return false unless param.param_type == "query" && identifier_like?(param.name)

      !object_lookup_callee(endpoint)
    end

    private def body_identifier_overwritten_from_path?(endpoint : Endpoint, param : Param) : Bool
      return false unless endpoint.details.technology == "kotlin_spring"
      return false unless BODY_LIKE_PARAM_TYPES.includes?(param.param_type)
      return false unless identifier_like?(param.name)

      path_identifiers = endpoint.params.select do |candidate|
        candidate.param_type == "path" && identifier_like?(candidate.name)
      end.map(&.name)
      return false if path_identifiers.empty?

      endpoint.details.code_paths.any? do |path_info|
        source = expanded_source_window(path_info, 12) || @reader.route_scope_snippet_for(path_info.path, path_info.line)
        source && body_identifier_assignment_from_path?(source, param.name, path_identifiers)
      end
    end

    private def body_identifier_assignment_from_path?(source : String, body_identifier : String, path_identifiers : Array(String)) : Bool
      path_pattern = path_identifiers.map { |name| Regex.escape(name) }.join("|")
      return false if path_pattern.empty?

      source.matches?(Regex.new("\\b#{Regex.escape(body_identifier)}\\s*=\\s*(?:this\\.)?(?:#{path_pattern})\\b"))
    end

    private def skip_param_tag_signal?(endpoint : Endpoint, param : Param, tag : Tag) : Bool
      return false unless tag.name == "idor" && tag.tagger == "Hunt"
      return false unless endpoint.details.technology == "kotlin_spring"
      return false unless endpoint.method == "GET"
      return false unless param.param_type == "query" && identifier_like?(param.name)

      !object_lookup_callee(endpoint)
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
        next if skip_tag_signal?(context, endpoint, tag)

        signal_kind = guard_tag?(tag) ? "auth_guard" : tag.name
        signal_name = guard_tag?(tag) ? guard_name_from_tag(tag) : tag_signal_name(tag)
        entry = AIContextEntry.new(
          signal_kind,
          signal_name,
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
          if websocket_cors_config_tag?(tag)
            context.push_source(AIContextEntry.new(
              "cors_policy",
              tag.description,
              source: tag.tagger,
              description: "WebSocket/STOMP endpoint CORS policy source derived from Spring endpoint registration.",
              path: anchor.try(&.path),
              line: anchor.try(&.line),
              confidence: 78,
              snippet: route_snippet
            ))
          end
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

    private def websocket_cors_config_tag?(tag : Tag) : Bool
      tag.name == "cors" &&
        tag.description.includes?("WebSocket/STOMP endpoint config")
    end

    private def skip_tag_signal?(context : AIContext, endpoint : Endpoint, tag : Tag) : Bool
      return false unless tag.name == "graphql"

      if graphql_operation_tag?(tag)
        context.signals.any? do |signal|
          signal.kind == "graphql" && signal.description == tag.description
        end
      else
        endpoint.tags.any? { |candidate| graphql_operation_tag?(candidate) }
      end
    end

    private def tag_signal_name(tag : Tag) : String
      return tag.description if graphql_operation_tag?(tag)

      tag.name
    end

    private def graphql_operation_tag?(tag : Tag) : Bool
      tag.name == "graphql" && tag.description.matches?(/^[A-Z][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*$/)
    end

    GRAPHQL_RESOLVER_ANNOTATION_PATTERN = /@(QueryMapping|MutationMapping|SchemaMapping|SubscriptionMapping|BatchMapping|DgsQuery|DgsMutation|DgsData|DgsSubscription)\b/

    private def add_graphql_resolver_signal(context : AIContext, endpoint : Endpoint)
      return unless graphql_endpoint?(endpoint)
      return if context.signals.any? { |s| s.kind == "graphql_resolver" }

      resolver_path = endpoint.details.code_paths.find do |path_info|
        next false unless path_info.path.ends_with?(".kt") || path_info.path.ends_with?(".java")

        snippet = @reader.route_scope_snippet_for(path_info.path, path_info.line)
        snippet.try(&.matches?(GRAPHQL_RESOLVER_ANNOTATION_PATTERN)) || false
      end
      return unless resolver_path

      resolver_snippet = @reader.route_scope_snippet_for(resolver_path.path, resolver_path.line)
      context.push_signal(AIContextEntry.new(
        "graphql_resolver",
        graphql_operation_name(endpoint),
        source: "resolver",
        description: "Spring GraphQL resolver implementation for this GraphQL operation.",
        path: resolver_path.path,
        line: resolver_path.line,
        confidence: 90,
        snippet: resolver_snippet
      ))
    end

    private def graphql_operation_name(endpoint : Endpoint) : String
      graphql_tag = endpoint.tags.find { |tag| tag.name == "graphql" && tag.description.includes?(".") }
      graphql_tag.try(&.description) || endpoint.url
    end

    # The mobile-only sinks (webview_load / intent_redirect) are matched
    # only for deep-link endpoints; HTTP route handlers get the catalog
    # without them. See `MOBILE_SINK_KINDS` in patterns.cr.
    private def sink_patterns_for(endpoint : Endpoint) : Array(PatternDefinition)
      endpoint.mobile? ? SINK_PATTERNS : NON_MOBILE_SINK_PATTERNS
    end

    private def add_callee_entries(context : AIContext, endpoint : Endpoint)
      sink_patterns = sink_patterns_for(endpoint)
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

        if raw_sink = PatternMatcher.detect_from_patterns(callee.name, callee_snippet, sink_patterns, callee.path, callee.line, "callee")
          sink = normalize_mobile_sink(endpoint, raw_sink)
          context.push_sink(enrich_callee_sink(sink, callee, callee_snippet))
        end

        if validator = PatternMatcher.detect_from_patterns(callee.name, callee_snippet, VALIDATOR_PATTERNS, callee.path, callee.line, "callee")
          context.push_validator(validator)
        end
      end
    end

    private def enrich_callee_sink(sink : AIContextEntry, callee : Callee, snippet : String?) : AIContextEntry
      return sink unless sink.kind == "outbound_http"
      return sink unless uri = outbound_uri_from_snippet(snippet, callee.line)

      AIContextEntry.new(
        sink.kind,
        "#{callee.name} #{uri}",
        source: sink.source,
        description: "#{sink.description} Target URI: #{uri}.",
        path: sink.path,
        line: sink.line,
        confidence: sink.confidence,
        snippet: sink.snippet
      )
    end

    private def normalize_mobile_sink(endpoint : Endpoint, sink : AIContextEntry) : AIContextEntry
      return sink unless mobile_url_download_sink?(endpoint, sink)

      AIContextEntry.new(
        "outbound_http",
        sink.name,
        source: sink.source,
        description: "Potential outbound HTTP/client sink inferred from mobile URL lookup/download flow",
        path: sink.path,
        line: sink.line,
        confidence: sink.confidence,
        snippet: sink.snippet
      )
    end

    private def mobile_url_download_sink?(endpoint : Endpoint, sink : AIContextEntry) : Bool
      return false unless endpoint.mobile?
      return false unless sink.kind == "file_io"

      evidence = "#{sink.name}\n#{sink.snippet || ""}"
      return false unless evidence.matches?(/\bdownload/i)
      return false unless evidence.matches?(/\b(?:url|uri|https?|deeplink|feedUrl|lookupUrl|prepareUrl)\b/i)
      return false if evidence.matches?(/\b(?:File\.(?:open|read|write)|readFile|writeFile|send_file|sendFile|upload|file(?:Name|Path)?|path)\b/i)

      true
    end

    private def outbound_uri_from_snippet(snippet : String?, line : Int32?) : String?
      return unless snippet

      if line && (line_match = snippet.match(/(?:^|\|\s*)#{line}:\s*([^|]+)/))
        if uri_match = line_match[1].match(/\.\s*uri\s*\(\s*["']([^"']+)["']/)
          return uri_match[1]
        end
        if uri_match = line_match[1].match(/\.\s*(?:getForObject|postForObject|exchange)\s*\(\s*["']([^"']+)["']/)
          return uri_match[1]
        end
      end

      match = snippet.match(/\.\s*(?:uri|getForObject|postForObject|exchange)\s*\(\s*["']([^"']+)["']/)
      return unless match

      match[1]
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
        sink_patterns_for(endpoint).each do |pattern|
          next if context.sinks.any? { |s| s.kind == pattern.kind }
          if raw_sink = PatternMatcher.detect_single_pattern(pattern, "", snippet, path_info.path, path_info.line, "route_source")
            context.push_sink(normalize_mobile_sink(endpoint, raw_sink))
          end
        end
        add_spring_mvc_template_render_sink(context, endpoint, path_info, snippet)

        VALIDATOR_PATTERNS.each do |pattern|
          next if context.validators.any? { |v| v.kind == pattern.kind }
          if validator = PatternMatcher.detect_single_pattern(pattern, "", snippet, path_info.path, path_info.line, "route_source")
            context.push_validator(validator)
          end
        end

        add_query_parameter_binding_validator(context, path_info)
        add_kotlin_collection_id_lookup_entries(context, endpoint, path_info, snippet)
        add_request_cookie_source(context, path_info, snippet)
        add_foreign_identifier_write_signal(context, endpoint, path_info, snippet)
      end
    end

    private def add_query_parameter_binding_validator(context : AIContext, path_info : PathInfo)
      return if context.validators.any? { |validator| validator.kind == "query_parameter_binding" }

      pattern = VALIDATOR_PATTERNS.find { |candidate| candidate.kind == "query_parameter_binding" }
      return unless pattern

      source = expanded_source_window(path_info, 8)
      return unless source

      if validator = PatternMatcher.detect_single_pattern(pattern, "", source, path_info.path, path_info.line, "route_source")
        context.push_validator(validator)
      end
    end

    REQUEST_COOKIE_READ_PATTERN = /\b[A-Za-z_][A-Za-z0-9_]*\s*\.\s*(?:cookies\b|getCookies\s*\()/i

    private def add_request_cookie_source(context : AIContext, path_info : PathInfo, snippet : String)
      return if context.sources.any? { |source| source.kind == "request_input" && source.name.starts_with?("cookie.") }
      return unless snippet.matches?(REQUEST_COOKIE_READ_PATTERN)

      context.push_source(AIContextEntry.new(
        "request_input",
        "cookie.#{request_cookie_source_name(snippet)}",
        source: "route_source",
        description: "HTTP cookie value read from the request.",
        path: path_info.path,
        line: path_info.line,
        confidence: 82,
        snippet: snippet
      ))
    end

    private def request_cookie_source_name(snippet : String) : String
      if match = snippet.match(/\bname\s*==\s*["']([^"']+)["']/)
        return match[1]
      end
      if snippet.matches?(/\bget[A-Za-z0-9_]*RefreshToken[A-Za-z0-9_]*CookieName\s*\(/)
        return "refreshToken"
      end
      if snippet.matches?(/refresh[_-]?token/i)
        return "refreshToken"
      end

      "*"
    end

    SPRING_MVC_MAPPING_ANNOTATION = /@(GetMapping|PostMapping|PutMapping|PatchMapping|DeleteMapping|RequestMapping)\b/
    SPRING_MVC_VIEW_RETURN        = /\breturn\s+["']([^"']+)["']/
    SPRING_MVC_VIEW_EXPR          = /\bfun\b[^{\n]*:\s*String\b[^{\n]*=\s*["']([^"']+)["']/

    private def add_spring_mvc_template_render_sink(context : AIContext, endpoint : Endpoint, path_info : PathInfo, snippet : String)
      return unless endpoint.details.technology == "kotlin_spring"

      lines = @reader.lines_for(path_info.path)
      return if lines.empty?
      line = path_info.line
      return if line.nil? || line < 1 || line > lines.size

      route_idx = line - 1
      return unless spring_mvc_controller_class?(lines, route_idx)
      return if spring_mvc_response_body_scope?(lines, route_idx)
      return unless view_name = spring_mvc_returned_view_name(lines, route_idx)

      entry = AIContextEntry.new(
        "template_render",
        "Spring MVC view #{view_name}",
        source: "route_source",
        description: "Spring MVC controller returns a server-side view name; review template rendering and model data exposure for this endpoint.",
        path: path_info.path,
        line: line,
        confidence: 66,
        snippet: snippet
      )

      if index = context.sinks.index { |sink| sink.kind == "template_render" }
        context.sinks[index] = entry
      else
        context.push_sink(entry)
      end
    end

    private def spring_mvc_controller_class?(lines : Array(String), route_idx : Int32) : Bool
      class_idx = route_idx.downto(0).find { |idx| lines[idx].matches?(/\bclass\s+\w+/) }
      return false unless class_idx

      annotations = annotation_block_above(lines, class_idx)
      annotations.any?(&.matches?(/^@Controller(?:\b|\()/)) &&
        !annotations.any?(&.matches?(/^@RestController(?:\b|\()/))
    end

    private def spring_mvc_response_body_scope?(lines : Array(String), route_idx : Int32) : Bool
      if class_idx = route_idx.downto(0).find { |idx| lines[idx].matches?(/\bclass\s+\w+/) }
        return true if annotation_block_above(lines, class_idx).any?(&.matches?(/^@ResponseBody(?:\b|\()/))
      end

      scan_start = Math.max(route_idx - 6, 0)
      scan_end = Math.min(route_idx + 8, lines.size - 1)
      (scan_start..scan_end).any? { |idx| lines[idx].strip.matches?(/^@ResponseBody(?:\b|\()/) }
    end

    private def spring_mvc_returned_view_name(lines : Array(String), route_idx : Int32) : String?
      return unless lines[route_idx].matches?(SPRING_MVC_MAPPING_ANNOTATION)

      fun_idx = route_idx.upto(Math.min(route_idx + 8, lines.size - 1)).find { |idx| lines[idx].includes?("fun ") }
      return unless fun_idx

      scan_end = Math.min(fun_idx + 18, lines.size - 1)
      (fun_idx..scan_end).each do |idx|
        stripped = lines[idx].strip
        if match = stripped.match(SPRING_MVC_VIEW_EXPR)
          return normalized_spring_mvc_view_name(match[1])
        end
        if match = stripped.match(SPRING_MVC_VIEW_RETURN)
          return normalized_spring_mvc_view_name(match[1])
        end
        break if idx > fun_idx && stripped.matches?(SPRING_MVC_MAPPING_ANNOTATION)
      end

      nil
    end

    private def normalized_spring_mvc_view_name(name : String) : String?
      view = name.strip
      return if view.empty?
      return if view.starts_with?("redirect:") || view.starts_with?("forward:")
      view
    end

    private def annotation_block_above(lines : Array(String), idx : Int32) : Array(String)
      result = [] of String
      current = idx - 1
      while current >= 0
        stripped = lines[current].strip
        if stripped.empty?
          current -= 1
          next
        end
        break unless stripped.starts_with?("@")

        result.unshift(stripped)
        current -= 1
      end
      result
    end

    KOTLIN_COLLECTION_ID_LOOKUP_PATTERN        = /\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*(firstOrNull|find|singleOrNull)\s*\{[^}]*\b(?:it|[A-Za-z_][A-Za-z0-9_]*)\.(?:id|[A-Za-z_][A-Za-z0-9_]*Id)\s*==/i
    KOTLIN_COLLECTION_ID_LOOKUP_THROWS_PATTERN = /\b(?:firstOrNull|find|singleOrNull)\s*\{[^}]*\b(?:id|[A-Za-z_][A-Za-z0-9_]*Id)\b[^}]*\}[\s\S]{0,180}(?:\?:\s*throw|\borElseThrow\b|\bthrow\s+\w*(?:NotFound|NotExist|Missing)\b)/i

    private def add_kotlin_collection_id_lookup_entries(context : AIContext, endpoint : Endpoint, path_info : PathInfo, snippet : String)
      return unless object_lookup_identifier_param?(endpoint)
      return unless match = snippet.match(KOTLIN_COLLECTION_ID_LOOKUP_PATTERN)

      lookup_name = "#{match[1]}.#{match[2]}(id)"

      unless context.signals.any? { |s| s.kind == "object_lookup" } || object_lookup_callee(endpoint)
        context.push_signal(AIContextEntry.new(
          "object_lookup",
          lookup_name,
          source: "route_source",
          description: "Identifier input is used in a Kotlin collection lookup; review object-level authorization and not-found behavior around this access.",
          path: path_info.path,
          line: path_info.line,
          confidence: 54,
          snippet: snippet
        ))
      end

      return if context.validators.any? { |v| v.kind == "existence_validation" }
      return unless snippet.matches?(KOTLIN_COLLECTION_ID_LOOKUP_THROWS_PATTERN)

      context.push_validator(AIContextEntry.new(
        "existence_validation",
        lookup_name,
        source: "route_source",
        description: "Existence or not-found validation inferred from a Kotlin collection id lookup followed by an exception path.",
        path: path_info.path,
        line: path_info.line,
        confidence: 58,
        snippet: snippet
      ))
    end

    FOREIGN_IDENTIFIER_ASSIGNMENT_PATTERN = /\b([A-Za-z_][A-Za-z0-9_]*Id)\s*=\s*(?:[A-Za-z_][A-Za-z0-9_]*\.)?([A-Za-z_][A-Za-z0-9_]*Id)\b/
    KOTLIN_WRITE_IN_SNIPPET_PATTERN       = /\b(?:save|insert|persist|update|create|add|addAll)\s*\(|\.\s*(?:save|insert|persist|update|add|addAll)\s*\(/i

    private def add_foreign_identifier_write_signal(context : AIContext, endpoint : Endpoint, path_info : PathInfo, snippet : String)
      return if context.signals.any? { |s| s.kind == "foreign_identifier_write" }
      return unless STATE_CHANGING_METHODS.includes?(endpoint.method)
      return if context.signals.any? { |s| s.kind == "object_lookup" }
      return if object_lookup_callee(endpoint)
      return if context.validators.any? { |v| v.kind == "existence_validation" }
      return unless endpoint.params.any? do |param|
                      BODY_LIKE_PARAM_TYPES.includes?(param.param_type) &&
                      !param.name.starts_with?("graphql_") &&
                      identifier_like?(param.name)
                    end

      detection_source = expanded_source_window(path_info, 18) || snippet
      return unless detection_source.matches?(KOTLIN_WRITE_IN_SNIPPET_PATTERN)
      return unless match = detection_source.match(FOREIGN_IDENTIFIER_ASSIGNMENT_PATTERN)
      # A same-named assignment (`userId = request.userId`, `val id = dto.id`)
      # is a local read/copy, not a foreign id flowing into a different field.
      # The real signal is a *different* destination field (`authorId = userId`).
      return if match[1] == match[2]

      context.push_signal(AIContextEntry.new(
        "foreign_identifier_write",
        "#{match[1]}=#{match[2]}",
        source: "route_source",
        description: "Identifier-like request input is assigned into a persisted object reference without a detected lookup or existence check; review ownership and foreign-object validation.",
        path: path_info.path,
        line: path_info.line,
        confidence: 56,
        snippet: snippet
      ))
    end

    private def expanded_source_window(path_info : PathInfo, radius : Int32) : String?
      line = path_info.line
      return unless line
      return if line < 1

      lines = @reader.lines_for(path_info.path)
      return if lines.empty? || line > lines.size

      start_idx = Math.max(line - 1, 0)
      end_idx = Math.min(line + radius - 1, lines.size - 1)
      window = (start_idx..end_idx).map { |idx| lines[idx].strip }.join("\n").strip
      window.empty? ? nil : window
    end

    private def add_missing_guard_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return unless STATE_CHANGING_METHODS.includes?(endpoint.method)
      return if graphql_read_endpoint?(endpoint)
      return if read_only_post_endpoint?(endpoint)

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
      return if auth_lifecycle_endpoint?(endpoint) && !path_id_param

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

    AUTH_NAMESPACE_PATTERN            = /(?:^|\/)auth(?:\/|$)/i
    AUTH_LIFECYCLE_SEGMENT_PATTERN    = /(?:^|\/)(login|log[_-]?in|logout|log[_-]?out|authenticate|refresh[_-]?token|verify|verification|reset[_-]?password|forgot[_-]?password|password[_-]?reset)(?:\/|$)/i
    ACCOUNT_REGISTER_SEGMENT_PATTERN  = /(?:^|\/)(register|sign[_-]?up|signup)(?:\/|$)/i
    ACCOUNT_NAMESPACE_SEGMENT_PATTERN = /(?:^|\/)(user|users|account|accounts|auth)(?:\/|$)/i

    private def auth_lifecycle_endpoint?(endpoint : Endpoint) : Bool
      return true if endpoint.url.matches?(AUTH_NAMESPACE_PATTERN)
      return true if endpoint.url.matches?(AUTH_LIFECYCLE_SEGMENT_PATTERN)

      endpoint.url.matches?(ACCOUNT_REGISTER_SEGMENT_PATTERN) &&
        endpoint.url.matches?(ACCOUNT_NAMESPACE_SEGMENT_PATTERN)
    end

    private def graphql_read_endpoint?(endpoint : Endpoint) : Bool
      return false unless graphql_endpoint?(endpoint)
      !graphql_mutation_endpoint?(endpoint)
    end

    READ_ONLY_POST_CALLEE_PATTERN = /(?:^|[.:])(?:find|findAll|findOne|findBy\w+|get|list|listAll|count|search|query|retrieve)\w*\b/i

    # A mutating verb anywhere in the callee name (start, after a separator, or
    # as a CamelCase segment) disqualifies the endpoint from "read-only POST".
    # Without this, a callee like `getOrCreate`/`findAndDelete` matches the
    # read-only pattern via its leading read verb, silently suppressing the
    # state-change review signal on an endpoint that does mutate.
    MUTATING_POST_CALLEE_PATTERN = /(?:\A|[.:_])(?:create|save|update|delete|insert|remove|destroy|modify|persist|revoke|store)|(?:Create|Save|Update|Delete|Insert|Remove|Destroy|Modify|Persist|Revoke|Store)/

    private def read_only_post_endpoint?(endpoint : Endpoint) : Bool
      return false unless endpoint.method == "POST"
      return false if endpoint.params.any? { |param| BODY_LIKE_PARAM_TYPES.includes?(param.param_type) }
      return false if endpoint.callees.empty?
      return false if endpoint.callees.any? { |callee| callee.name.matches?(MUTATING_POST_CALLEE_PATTERN) }

      endpoint.callees.all? { |callee| callee.name.matches?(READ_ONLY_POST_CALLEE_PATTERN) }
    end

    private def graphql_endpoint?(endpoint : Endpoint) : Bool
      return true if endpoint.url.includes?("/graphql#")

      endpoint.tags.any? do |tag|
        tag.name == "graphql" || tag.name == "graphql-root"
      end
    end

    GRAPHQL_OPERATION_ROOTS = ["Query", "Mutation", "Subscription"]

    private def graphql_field_endpoint?(endpoint : Endpoint) : Bool
      return false unless graphql_endpoint?(endpoint)

      if root_tag = endpoint.tags.find { |tag| tag.name == "graphql-root" }
        return !GRAPHQL_OPERATION_ROOTS.includes?(root_tag.description)
      end

      if match = endpoint.url.match(/\/graphql#([^.#]+)\./)
        return !GRAPHQL_OPERATION_ROOTS.includes?(match[1])
      end

      false
    end

    private def graphql_mutation_endpoint?(endpoint : Endpoint) : Bool
      return true if endpoint.url.includes?("#Mutation.")

      endpoint.tags.any? do |tag|
        (tag.name == "graphql-root" && tag.description == "Mutation") ||
          (tag.name == "graphql" && tag.description.starts_with?("Mutation."))
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
