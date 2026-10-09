require "colorize"
require "crest"
require "openssl"
require "wait_group"
require "./logger"
require "./skipped_files"
require "../utils/utils"
require "../utils/http_symbols"
require "../utils/url_origin"
require "../utils/redact"

# Max concurrent in-flight probe requests and the outbound TLS context, shared
# by every class that fires requests at discovered endpoints. Bounds the
# fiber/socket fan-out so a large endpoint set can't exhaust file descriptors. Backed by the validated
# --concurrency value (already clamped to a sane ceiling).
#
# A module rather than a `Deliver` method because `StatusCodeProbe` is
# deliberately not a `Deliver` subclass (see its class comment) yet has to
# bound its fan-out exactly the same way. Keeping the rule in one place is what
# stops the two from drifting again: the status probe was strictly sequential
# for exactly as long as this lived on `Deliver` alone.
module ProbeConcurrency
  DEFAULT_PROBE_CONCURRENCY = 16

  protected def concurrency_limit : Int32
    n = @options["concurrency"]?.try(&.to_s.to_i?) || 0
    n > 0 ? n : DEFAULT_PROBE_CONCURRENCY
  end

  # TLS context for outbound delivery. Verifying (secure) by default; the
  # old behaviour skipped verification unconditionally, silently exposing
  # the endpoint catalog to MITM on the way to a webhook / Elasticsearch.
  # `--tls-skip-verify` restores the insecure context for self-signed
  # internal endpoints.
  protected def tls_context : OpenSSL::SSL::Context::Client
    if any_to_bool(@options["tls_skip_verify"]?)
      OpenSSL::SSL::Context::Client.insecure
    else
      OpenSSL::SSL::Context::Client.new
    end
  end
end

class Deliver
  include ProbeConcurrency

  @logger : NoirLogger
  @options : Hash(String, YAML::Any)
  getter proxy : String
  getter headers : Hash(String, String) = {} of String => String
  @matchers : Array(String)
  @filters : Array(String)
  # Origin of `--url`, resolved lazily (see `target_origin`) and the set of
  # off-target origins already warned about, so the warning fires once per
  # host instead of once per endpoint.
  @target_origin : String? = nil
  @target_origin_resolved = false
  @offhost_origins = Set(String).new
  @offhost_mutex = Mutex.new

  def initialize(options : Hash(String, YAML::Any))
    @options = options
    @proxy = options["probe_via"].to_s
    @logger = NoirLogger.from_options(options)

    options["probe_header"].as_a.each do |set_header|
      raw = set_header.to_s
      # Only split on the first colon so values that contain colons
      # (e.g. `Authorization: Bearer aaa:bbb`, `X-Time: 12:34:56`)
      # keep their full payload after the header name.
      colon_index = raw.index(':')
      if colon_index.nil?
        # Pre-fix this dropped silently. A typo like
        # `--probe-header "X-Auth tok123"` (missing colon) meant the
        # auth never got sent and the user wondered why every probe
        # returned 401.
        STDERR.puts "WARNING: --probe-header value '#{Noir::Redact.named_value(raw)}' is missing a ':' — expected 'Name: value' format. Skipping.".colorize(:yellow)
        next
      end

      name = raw[0...colon_index]
      if name.empty?
        STDERR.puts "WARNING: --probe-header value '#{Noir::Redact.named_value(raw)}' has an empty header name (nothing before ':'). Skipping.".colorize(:yellow)
        next
      end

      value = raw[(colon_index + 1)..]
      value = value.lstrip(' ') unless value.empty?
      @headers[name] = value
    end

    @matchers = options["probe_match"].as_a.map(&.to_s).reject(&.empty?)
    unless @matchers.empty?
      @logger.info "#{@matchers.size} matchers added."
    end

    @filters = options["probe_skip"].as_a.map(&.to_s).reject(&.empty?)
    unless @filters.empty?
      @logger.info "#{@filters.size} filters added."
    end
  end

  def apply_all(endpoints : Array(Endpoint))
    result = endpoints
    @logger.debug "Matchers: #{@matchers}"
    @logger.debug "Filters: #{@filters}"

    unless @matchers.empty?
      @logger.info "Applying matchers"
      result = apply_matchers(result)
    end

    unless @filters.empty?
      @logger.info "Applying filters"
      result = apply_filters(result)
    end

    result
  end

  # An endpoint that satisfies several matchers (e.g. ["GET", "GET:/api"])
  # is kept once, logged against the first.
  def apply_matchers(endpoints : Array(Endpoint))
    endpoints.select do |endpoint|
      if matcher = @matchers.find { |pattern| matches_pattern?(endpoint, pattern) }
        @logger.debug "Endpoint '#{endpoint.method} #{endpoint.url}' matched with '#{matcher}'."
      end
      matcher
    end
  end

  def apply_filters(endpoints : Array(Endpoint))
    endpoints.reject do |endpoint|
      if filter = @filters.find { |pattern| matches_pattern?(endpoint, pattern) }
        @logger.debug "Endpoint '#{endpoint.method} #{endpoint.url}' filtered with '#{filter}'."
      end
      filter
    end
  end

  # Requests that never completed during the last `run` — connection
  # refused, TLS handshake rejected, DNS failure, timeout. Deliberately
  # *not* incremented for an HTTP error response: a 404 or 500 means the
  # probe was delivered and answered. Exposed so the distinction is
  # assertable, since the count is otherwise only visible as a log line.
  getter undeliverable_count : Int32 = 0

  # Fires one request per requestable verb of every probeable endpoint,
  # bounded by --concurrency, and returns how many never completed. Every
  # request goes out with `handle_errors: false, max_redirects: 0` — see the
  # comment on SendReq#run for why the two are inseparable.
  protected def probe_all(endpoints : Array(Endpoint), tls : OpenSSL::SSL::Context::Client, label : String,
                          p_addr : String? = nil, p_port : Int32? = nil) : Int32
    wg = WaitGroup.new
    failures = Atomic(Int32).new(0)
    # Bound in-flight requests to --concurrency so a large endpoint set can't
    # spawn thousands of sockets at once and hit "Too many open files".
    sem = Channel(Nil).new(concurrency_limit)

    apply_all(endpoints).each do |endpoint|
      next if endpoint.non_http? # can't HTTP-probe an app deep link or CLI command
      # `internal` is set by the Spring analyzer for `@FeignClient` /
      # `@HttpExchange` interfaces, which declare requests the app makes to
      # *other* services — they are not routes this app serves. Probing them
      # fired those paths at the `-u` target, which does not own them. They
      # stay in the catalog (export ships it as data); only the probe skips.
      next if endpoint.internal
      # Built once per endpoint, outside the spawn: every fiber for this
      # endpoint sends the same headers and body.
      request_headers = probe_headers(endpoint)
      endpoint_hash = endpoint.params_to_hash
      is_json = !endpoint_hash["json"].empty?
      body = is_json ? endpoint_hash["json"] : endpoint_hash["form"]
      requestable_http_methods(endpoint.method).each do |request_method|
        wg.add(1)
        sem.send(nil) # acquire a slot (blocks once `concurrency_limit` are in flight)
        spawn do
          Crest::Request.execute(
            method: get_symbol(request_method),
            url: probe_url(endpoint, request_method),
            p_addr: p_addr,
            p_port: p_port,
            tls: tls,
            user_agent: "Noir/#{Noir::VERSION}",
            params: endpoint_hash["query"],
            form: body,
            headers: request_headers,
            json: is_json,
            handle_errors: false,
            max_redirects: 0,
            connect_timeout: PROBE_CONNECT_TIMEOUT,
            read_timeout: probe_read_timeout
          )
        rescue e
          failures.add(1)
          @logger.debug "Exception during #{label}"
          @logger.debug_sub e
        ensure
          sem.receive # release the slot
          wg.done
        end
      end
    end

    wg.wait
    @undeliverable_count = failures.get
  end

  # POSTs the JSON document the block builds (`{url, body}`) to an export
  # receiver. A failure anywhere — building the body, parsing the URL, the
  # request itself — is warned and recorded rather than raised: a swallowed
  # debug line let the user believe the catalog was delivered, and a warning
  # alone let a pipeline whose whole purpose is shipping the catalog go green
  # under `--strict` while shipping nothing.
  #
  # Crest's `Request.execute` only recognizes `form:` as the body source —
  # `body:` is silently swallowed into `**options` and the request goes out
  # with Content-Length: 0. Combined with `json: true`, `form:` ships the raw
  # String through as the JSON payload (verified against Crest 1.4.x in spec).
  protected def post_export(target : String, warn_label : String, gap_label : String, &)
    url, body = yield

    # Dup the user-supplied headers so the JSON headers don't bleed into
    # @headers.
    export_headers = @headers.dup
    export_headers["Content-Type"] = "application/json"
    export_headers["Accept"] = "application/json"

    Crest::Request.execute(
      method: :post,
      url: url,
      tls: tls_context,
      user_agent: "Noir/#{Noir::VERSION}",
      form: body,
      headers: export_headers,
      json: true,
      connect_timeout: EXPORT_CONNECT_TIMEOUT,
      read_timeout: export_read_timeout
    )
  rescue e
    @logger.warning "#{warn_label} delivery to #{target} failed: #{e.message}"
    @logger.debug_sub e
    Noir::SkippedFiles.record_gap(
      Noir::SkippedFiles::DELIVER_SCOPE,
      "#{gap_label} delivery to #{target} failed: #{e.message.presence || e.class.name}"
    )
  end

  # Crest defaults both `connect_timeout` and `read_timeout` to nil, i.e.
  # no timeout at all, and every delivery class relied on that default. A
  # host that accepted the connection and then went quiet blocked forever:
  #
  #   - probe / proxy: the stalled request keeps holding its --concurrency
  #     slot, so enough blackholed hosts starve every remaining endpoint.
  #   - export: `deliver` runs at the end of `analyze`, which is BEFORE
  #     `report` is called, so a hung Elasticsearch or webhook host hangs
  #     noir before any output is written and the user loses the whole scan.
  #
  # Values are deliberately generous rather than snappy. A probe's purpose
  # is to *deliver* the request (so an intercepting proxy or the app's own
  # logs see it); a slow-but-working target answering in 12s should not
  # start being reported as undeliverable. These bound the pathological
  # case without second-guessing a live one.
  PROBE_CONNECT_TIMEOUT = 5.seconds
  PROBE_READ_TIMEOUT    = 15.seconds

  # Export ships one request carrying the entire catalog, so it gets more
  # room: the body can be megabytes and the receiver may index it inline.
  EXPORT_CONNECT_TIMEOUT = 10.seconds
  EXPORT_READ_TIMEOUT    = 60.seconds

  # Path-param names that name a number. A framework route constrained to an
  # integer (`/users/{id:int}`, Django's `<int:pk>`) rejects a word, so these
  # get `1`; anything else gets a harmless string.
  NUMERIC_PATH_PARAM_RE = /\A(?:.*_)?(?:id|ids|pk|no|num|number|count|page|size|limit|offset|index|idx|version|seq|year|month|day|port)\z/i

  # The URL to probe for this endpoint and verb. Leaves `endpoint.url`
  # untouched — the reported catalog keeps the template, which is what the
  # user wants to read; only the outbound request is concretized.
  #
  # Templates are filled only for the read-only verbs (`SAFE_HTTP_METHODS`,
  # QUERY included), on purpose.
  #
  # `register_path_params` in the optimizer only substitutes a placeholder when
  # `--set-pvalue-path` supplied a value, so on a default scan `/users/{id}`
  # is probed literally and 404s. Filling it makes the probe actually reach
  # the route — but it also makes destructive verbs real: `DELETE
  # /users/{id}` is a harmless 404 today and would become `DELETE /users/1`
  # against a live record. Read-only verbs get the benefit without that risk;
  # for the rest the literal template still reaches an intercepting proxy,
  # where the user can edit and replay it deliberately.
  protected def probe_url(endpoint : Endpoint, request_method : String) : String
    return endpoint.url unless SAFE_HTTP_METHODS.includes?(request_method.upcase)

    fillers = {} of String => String
    endpoint.params.each do |param|
      next unless param.param_type == "path"
      # A non-empty value means --set-pvalue-path already applied and the
      # optimizer substituted it; nothing left to fill.
      next unless param.value.empty?
      next if param.name.empty?

      fillers[param.name] = NUMERIC_PATH_PARAM_RE.matches?(param.name) ? "1" : "noir"
    end
    return endpoint.url if fillers.empty?

    url = fill_delimited_path_params(endpoint.url, fillers)

    # Longest name first. The `:name` form has no closing delimiter, so a
    # param whose name merely *starts with* another's used to be eaten by the
    # shorter substitution in declaration order: Express `/u/:id/:idx` with
    # params [id, idx] was probed as `/u/1/1x`, a path the app does not route.
    fillers.keys.sort_by! { |name| -name.size }.each do |name|
      filler = fillers[name]
      escaped = Regex.escape(name)
      # `:name` only counts at a segment boundary. Anchoring to a preceding
      # `/` keeps the scheme/port colon in `http://host:8080` and embedded
      # example text like `/profiles/celeb_:USERNAME` out of it. The trailing
      # lookahead ends the name at the first character that can't be part of
      # one, so `:id` no longer matches the head of `:idx` while Play-style
      # `/:lang.json` and `/:id-suffix` still fill.
      url = url.gsub(/(\A|\/):#{escaped}(?![A-Za-z0-9_])/) { "#{$1}#{filler}" }
    end

    url
  end

  # Replaces every `{...}` / `<...>` placeholder whose name is a fillable path
  # param. A plain `gsub("{#{name}}")` only ever matched the bare form, so the
  # typed and constrained spellings frameworks put *around* the name survived
  # into the request and the probe hit a literal template:
  #
  #   Django / Flask  `<int:pk>`, `<str:module>`, `<path:subpath>`
  #   chi / gorilla   `{sha:[a-f0-9]{7,64}}`
  #   FastAPI         `{file_path:path}`
  #   Ktor            `{segments...}`
  #   ASP.NET / Rails `{*slug}`, `{slug*}`
  #
  # A brace constraint can itself contain braces (`{7,64}`), so the closing
  # delimiter is found by depth counting rather than by a regex.
  private def fill_delimited_path_params(url : String, fillers : Hash(String, String)) : String
    return url unless url.includes?('{') || url.includes?('<')

    chars = url.chars
    filled = String::Builder.new(url.bytesize)
    index = 0
    while index < chars.size
      open = chars[index]
      close = case open
              when '{' then '}'
              when '<' then '>'
              end
      if close.nil?
        filled << open
        index += 1
        next
      end

      depth = 1
      cursor = index + 1
      while cursor < chars.size
        char = chars[cursor]
        if char == open
          depth += 1
        elsif char == close
          depth -= 1
          break if depth.zero?
        end
        cursor += 1
      end

      if depth.zero?
        body = chars[(index + 1)...cursor].join
        # The raw body first: an analyzer that reports the decorated
        # spelling as the param name (Ktor's `segments...`) still gets
        # its placeholder filled, exactly as the old literal replace did.
        name = fillers.has_key?(body) ? body : placeholder_param_name(body, open == '{')
        if name && (filler = fillers[name]?)
          filled << filler
          index = cursor + 1
          next
        end
      end

      filled << open
      index += 1
    end

    filled.to_s
  end

  # The param name inside one placeholder body, or nil when there is none.
  # A colon separates the name from a type or a regex constraint, but the two
  # families put it on opposite sides: `<int:pk>` names the converter first,
  # `{sha:[a-f0-9]+}` names the param first.
  private def placeholder_param_name(body : String, braces : Bool) : String?
    return if body.empty?

    name = body
    if colon = name.index(':')
      name = braces ? name[0, colon] : name[(colon + 1)..]
    end
    # Tail-card, catch-all and optional markers decorate the bare name.
    name = name.rchop("...")
    name = name.strip("*?")
    name.empty? ? nil : name
  end

  # Headers for one probe: the analyzer-discovered `header` and `cookie`
  # params for this endpoint, with the user's `--probe-header` values layered
  # on top so an explicit flag always wins over a discovered default.
  #
  # Probes previously read only the query/json/form buckets, so an endpoint
  # whose auth is a discovered `X-API-Key` header was probed without it and
  # came back 401 for no visible reason.
  #
  # Returns a fresh Hash every call. `@headers` is shared across every probe
  # fiber, so merging into it in place would race and leak one endpoint's
  # headers onto another's request.
  protected def probe_headers(endpoint : Endpoint) : Hash(String, String)
    user_headers = user_headers_for(endpoint)
    params = endpoint.params_to_hash
    discovered = params["header"]
    cookies = params["cookie"]
    return user_headers if discovered.empty? && cookies.empty?

    result = {} of String => String
    discovered.each { |name, value| result[name] = value }
    # One `Cookie` header carries the whole jar, per RFC 6265.
    unless cookies.empty?
      result["Cookie"] = cookies.map { |name, value| "#{name}=#{value}" }.join("; ")
    end
    result.merge(user_headers)
  end

  # `--probe-header` values are the user's own secrets — a session cookie, a
  # bearer token for the app they are testing. They are meant for the `-u`
  # target and nowhere else.
  #
  # Most endpoints are paths that `combine_url_and_endpoints` prefixed with
  # `-u`, so they carry the target's origin by construction. But an endpoint
  # that already had a scheme and host in the source — an OAS `servers:`
  # entry, a HAR capture, a hosted-backend URL in a schema-generated client —
  # is passed through untouched by design, and the source is the tree being
  # scanned. Attaching the token to those means a repo can name a host and
  # have Noir hand the user's credential to it.
  #
  # `send_req` already refuses to follow redirects for exactly this reason
  # ("Crest copies the request headers onto the redirected request, including
  # a --probe-header Authorization token"); the same leak was reachable
  # without any redirect at all. Off-origin endpoints are still probed — that
  # part is intentional — just without the user's headers, and the dropped
  # hosts are named once so the omission is visible rather than silent.
  private def user_headers_for(endpoint : Endpoint) : Hash(String, String)
    return @headers if @headers.empty?

    target = target_origin
    # No `-u` means no origin to trust or distrust: the user pointed the
    # probe straight at whatever the catalog holds, so their headers ride
    # along as before.
    return @headers if target.nil?

    origin = Noir::UrlOrigin.of(endpoint.url)
    return @headers if origin.nil? || origin == target

    note_offhost_header_drop(origin)
    {} of String => String
  end

  private def target_origin : String?
    origin = @target_origin
    return origin unless origin.nil?
    return if @target_origin_resolved

    @target_origin_resolved = true
    @target_origin = Noir::UrlOrigin.of(@options["url"]?.to_s)
  end

  private def note_offhost_header_drop(origin : String)
    fresh = false
    @offhost_mutex.synchronize do
      unless @offhost_origins.includes?(origin)
        @offhost_origins << origin
        fresh = true
      end
    end
    return unless fresh

    @logger.warning "Probe: --probe-header values withheld from #{origin} — it is not the --url target. " \
                    "Endpoints on that host are still probed, without your headers."
  end

  # Read timeouts go through accessors rather than the constants directly so
  # a spec can subclass with sub-second values and still exercise the real
  # plumbing — asserting against the shipped defaults would mean 15-second
  # specs.
  protected def probe_read_timeout : Time::Span
    PROBE_READ_TIMEOUT
  end

  protected def export_read_timeout : Time::Span
    EXPORT_READ_TIMEOUT
  end

  # A `METHOD:url` pattern is only method-scoped when the token before the
  # first colon really is a verb an endpoint can carry. Splitting on *any*
  # colon read `--probe-skip https://api.example.com/admin` as method
  # `HTTPS` + url `//api.example.com/admin`, which matches nothing — so the
  # filter silently did nothing and every endpoint the user meant to skip
  # was probed anyway. That is the common shape, not an edge case: every
  # delivery target requires `-u`, which rewrites each endpoint to
  # `scheme://host/path`, so pasting a full URL into --probe-match /
  # --probe-skip is the natural thing to do. A `host:8080/x` pattern hit the
  # same hole.
  private def matches_pattern?(endpoint : Endpoint, pattern : String) : Bool
    colon_index = pattern.index(':')
    if colon_index && endpoint_method_token?(pattern[0...colon_index])
      method_pattern = pattern[0...colon_index].upcase
      url_pattern = pattern[(colon_index + 1)..]

      # Check if method matches and URL contains pattern
      return endpoint.method.upcase == method_pattern && endpoint.url.includes?(url_pattern)
    end

    # Pattern is just a method name. Matched against every verb an endpoint
    # can carry (not only the real HTTP ones) so `--probe-skip SEND` and
    # `--probe-skip CLI` filter the same way `SEND:/ws` does.
    if endpoint_method_token?(pattern)
      endpoint.method.upcase == pattern.upcase
    else
      # Backward compatibility: check URL
      endpoint.url.includes?(pattern)
    end
  end
end
