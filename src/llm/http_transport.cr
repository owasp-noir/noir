require "http_proxy"
require "http/client"
require "uri"
require "../utils/redact"

module LLM
  # Shared HTTP transport for the provider clients (OpenAI-compatible and
  # Ollama).
  #
  # Both clients used to post through the bare one-shot helpers
  # (`HTTP::Client.post` / `Crest.post`), which set no timeouts at all: a
  # provider that accepts the connection and then never answers — a wedged
  # local `ollama serve`, a proxy that black-holes the request, a hosted
  # endpoint that stalls mid-generation — hung the scan forever, with no
  # output and no indication of what it was waiting on. Requests now fail
  # after a bounded wait.
  #
  # It also retries the transient failures every hosted provider produces
  # (429 rate limits, 502/503 from a load balancer, a dropped socket).
  # Without that, one blip turned into a silent zero-endpoint AI result:
  # the clients map any failure to "", which the analyzer treats as "this
  # code defines no endpoints".
  module HttpTransport
    # Connecting is fast even for remote providers, so a short budget here
    # only shortens the "server isn't running" feedback loop that local
    # provider users (ollama, vLLM, LM Studio) hit most often.
    DEFAULT_CONNECT_TIMEOUT = 10.seconds

    # Generation is not fast: a large bundle against a CPU-bound local
    # model legitimately takes minutes, so the read budget is generous and
    # tunable rather than tight.
    DEFAULT_TIMEOUT = 300.seconds

    TIMEOUT_ENV         = "NOIR_AI_TIMEOUT"
    CONNECT_TIMEOUT_ENV = "NOIR_AI_CONNECT_TIMEOUT"

    MAX_ATTEMPTS = 3

    # Status codes worth another attempt: rate limits plus the transient
    # gateway/overload family. A 400/401/404 is a configuration problem
    # that retrying can only make slower.
    RETRYABLE_STATUS = Set{408, 425, 429, 500, 502, 503, 504, 529}

    # Cap on how long a provider's `Retry-After` may park the scan.
    MAX_RETRY_AFTER = 30.seconds

    MAX_ERROR_SNIPPET_SIZE = 1024

    def self.timeout : Time::Span
      duration_from_env(TIMEOUT_ENV) || DEFAULT_TIMEOUT
    end

    def self.connect_timeout : Time::Span
      duration_from_env(CONNECT_TIMEOUT_ENV) || DEFAULT_CONNECT_TIMEOUT
    end

    # Reads a timeout override, in seconds. Anything that isn't a positive
    # number (empty, `0`, a word) falls back to the default instead of
    # disabling the timeout — the point of the override is to move the
    # bound, not to remove it.
    def self.duration_from_env(name : String) : Time::Span?
      raw = ENV[name]?
      return if raw.nil?
      seconds = raw.strip.to_f?
      return if seconds.nil? || seconds <= 0
      seconds.seconds
    end

    def self.retryable_status?(code : Int32) : Bool
      RETRYABLE_STATUS.includes?(code)
    end

    # 1s, then 2s — bounded, and short enough that exhausting all attempts
    # still returns while the caller is waiting.
    def self.backoff(attempt : Int32) : Time::Span
      exponent = attempt < 1 ? 0 : attempt - 1
      (1 << exponent).seconds
    end

    # A provider that tells us when to come back (429s usually do) knows
    # better than the fixed backoff, as long as it stays within our cap.
    # Either form the RFC allows: delay-seconds or an HTTP-date.
    def self.retry_after(response : HTTP::Client::Response?) : Time::Span?
      raw = response.try(&.headers["Retry-After"]?).try(&.strip)
      return if raw.nil?
      span = raw.to_f?.try(&.seconds) || HTTP.parse_time(raw).try { |time| time - Time.utc }
      return if span.nil? || span <= Time::Span.zero
      span > MAX_RETRY_AFTER ? MAX_RETRY_AFTER : span
    end

    def self.retry_delay(response : HTTP::Client::Response?, attempt : Int32) : Time::Span
      retry_after(response) || backoff(attempt)
    end

    # `--ai-max-requests`: a hard bound on how many HTTP requests (retries
    # included) one run may send. 0 is unlimited. A request past the cap
    # fails like any other, so the files it was for are listed as coverage
    # gaps instead of silently dropped.
    class_property max_requests : Int32 = 0
    @@requests = Atomic(Int32).new(0)
    @@cap_warned = Atomic(Bool).new(false)

    # False once --ai-max-requests is used up: a skipped request, not a
    # provider failure.
    def self.requests_left? : Bool
      max = max_requests
      max <= 0 || @@requests.get < max
    end

    def self.claim_request : Bool
      max = max_requests
      return true if @@requests.add(1) < max || max <= 0
      @@requests.sub(1)
      STDERR.puts "WARNING: --ai-max-requests #{max} reached; the remaining AI requests are skipped." unless @@cap_warned.swap(true)
      false
    end

    # Token counts as the provider reports them: OpenAI-style `usage`
    # (`prompt_tokens` / `completion_tokens`, or Anthropic-style
    # `input_tokens` / `output_tokens`) and Ollama's eval counts. Read
    # with a regex rather than parsed: the model's own text is a JSON
    # string, where these keys would appear with escaped quotes.
    INPUT_TOKENS  = /"(?:prompt_tokens|input_tokens|prompt_eval_count)"\s*:\s*(\d+)/
    OUTPUT_TOKENS = /"(?:completion_tokens|output_tokens|eval_count)"\s*:\s*(\d+)/
    @@input_tokens = Atomic(Int64).new(0)
    @@output_tokens = Atomic(Int64).new(0)

    def self.record_usage(body : String) : Nil
      body.match(INPUT_TOKENS).try { |m| @@input_tokens.add(m[1].to_i64) }
      body.match(OUTPUT_TOKENS).try { |m| @@output_tokens.add(m[1].to_i64) }
    end

    # One line for the end of a run, nil when it made no AI requests.
    def self.usage_summary(cache_hits : Int32) : String?
      requests = @@requests.get
      return if requests == 0 && cache_hits == 0
      line = "AI usage: #{requests} HTTP request(s), #{cache_hits} cache hit(s)"
      input, output = @@input_tokens.get, @@output_tokens.get
      line += ", ~#{input} input / #{output} output tokens" if input + output > 0
      line
    end

    # Credentials this run has sent, so provider text that echoes one back
    # (some gateways quote the whole bearer token in a 401) never reaches
    # stderr or a CI log. Taken from the request headers rather than the
    # options, so whatever key a client actually sent is the one masked.
    @@secrets = Set(String).new
    @@secrets_mutex = Mutex.new

    def self.remember_secret(headers : HTTP::Headers) : Nil
      return unless auth = headers["Authorization"]?
      key = auth.sub(/\A\w+\s+/, "")
      @@secrets_mutex.synchronize { @@secrets << key }
    end

    @@cleartext_warned = Atomic(Bool).new(false)

    # A key over plain http:// to another machine is readable by anything on
    # the path. Local servers (ollama, vLLM, LM Studio) are the normal http
    # case and stay quiet.
    def self.warn_cleartext_key(uri : URI, headers : HTTP::Headers) : Nil
      return unless uri.scheme == "http" && headers.has_key?("Authorization")
      return if loopback?(uri.hostname.to_s)
      return if @@cleartext_warned.swap(true)
      STDERR.puts "WARNING: The AI API key is sent unencrypted over http:// to #{uri.hostname}; use https:// for a remote provider."
    end

    def self.loopback?(host : String) : Bool
      host = host.downcase
      return true if host == "localhost" || host.ends_with?(".localhost")
      return false unless Socket::IPAddress.valid?(host)
      ip = Socket::IPAddress.new(host, 0)
      # 0.0.0.0 dials this machine (OLLAMA_HOST=0.0.0.0 setups use it).
      ip.loopback? || ip.unspecified?
    end

    # Every provider error text that reaches stderr goes through here, so
    # it is also where the key is masked — before the cut, so a key
    # straddling it cannot leak its prefix.
    def self.truncate_error_snippet(body : String) : String
      body = Noir::Redact.secret(body, @@secrets_mutex.synchronize { @@secrets.dup })
      body.size > MAX_ERROR_SNIPPET_SIZE ? "#{body[0, MAX_ERROR_SNIPPET_SIZE]}..." : body
    end

    # A provider's final answer that was not a success and not worth
    # another attempt (a 400 naming a bad parameter, a prompt over the
    # context window). Handed back so the caller can read why.
    record Rejection, status : Int32, body : String, location : String? = nil

    # POSTs a JSON body and returns the response body, or nil when the
    # request could not be completed. Failures are reported here so every
    # provider path surfaces them the same way instead of each client
    # inventing its own (or, in Ollama's case, staying silent).
    def self.post_json(url : String, body : String, headers : HTTP::Headers) : String?
      result = post_json_result(url, body, headers)
      return result unless result.is_a?(Rejection)
      report(result)
      nil
    end

    # `post_json`, except a rejection is returned unreported, for a caller
    # that can recover from some of them.
    def self.post_json_result(url : String, body : String, headers : HTTP::Headers) : (String | Rejection)?
      remember_secret(headers)
      uri = URI.parse(url)
      warn_cleartext_key(uri, headers)
      proxy = proxy_for(uri)
      attempt = 0
      loop do
        attempt += 1
        return unless claim_request
        response = nil
        error = nil

        begin
          response = execute(uri, proxy, body, headers)
          if response.success?
            record_usage(response.body)
            return response.body
          end
        rescue e : IO::Error
          # Refused connections, timeouts and resets all arrive as
          # IO::Error subclasses.
          error = e
        end

        retryable = error ? !read_timeout?(error) : response.try { |r| retryable_status?(r.status_code) }
        if retryable && attempt < MAX_ATTEMPTS
          sleep retry_delay(response, attempt)
          next
        end

        if error
          STDERR.puts "WARNING: AI API request failed after #{attempt} attempt(s): #{error.class} (#{truncate_error_snippet(error.message.to_s)})"
        elsif response
          return Rejection.new(response.status_code, response.body, response.headers["Location"]?)
        end
        return
      end
    end

    def self.report(rejection : Rejection) : Nil
      # A redirect has no body worth showing; where it points is the fix
      # (usually an http:// provider URL that should be https://).
      detail = rejection.location.try { |loc| "redirected to #{truncate_error_snippet(loc)}; check the provider URL" } if (300..399).includes?(rejection.status)
      STDERR.puts "WARNING: AI API error (HTTP #{rejection.status}): #{detail || truncate_error_snippet(rejection.body)}"
    end

    # The proxy `HTTPS_PROXY` / `HTTP_PROXY` name for this request (lowercase
    # wins, as in curl), or nil to connect directly. Loopback and `NO_PROXY`
    # hosts always go direct: a local model behind a corporate proxy
    # variable must stay reachable.
    def self.proxy_for(uri : URI) : URI?
      host = uri.hostname.to_s.downcase
      return if loopback?(host) || no_proxy?(host)
      name = uri.scheme == "https" ? "https_proxy" : "http_proxy"
      raw = ENV[name]?.presence || ENV[name.upcase]?.presence
      return unless raw
      URI.parse(raw.includes?("://") ? raw : "http://#{raw}")
    end

    # ponytail: suffix and `*` entries only; CIDR ranges are not matched.
    def self.no_proxy?(host : String) : Bool
      list = ENV["no_proxy"]?.presence || ENV["NO_PROXY"]?.presence
      return false unless list
      list.split(',').any? do |raw|
        entry = raw.strip.downcase
        next true if entry == "*"
        entry = entry.lchop("*").lchop('.').sub(/:\d+\z/, "")
        !entry.empty? && (host == entry || host.ends_with?(".#{entry}"))
      end
    end

    # A read/write timeout runs out the long budget: usually the model was
    # still generating, and another attempt waits it out again and may pay
    # for the same generation twice. Only a connect timeout is worth
    # retrying. Matched on the message because the proxy shard re-wraps
    # the error as a plain IO::Error ("... (Read timed out)").
    # ponytail: event loops word it "Connect timed out" / "connect timed
    # out"; one that words it differently just loses the connect retry.
    def self.read_timeout?(error : Exception) : Bool
      message = error.message.to_s.downcase
      message.includes?("timed out") && !message.includes?("connect timed out")
    end

    # `HTTP::Client` has no proxy support of its own; the `http_proxy` shard
    # (already in the build through crest) adds `#proxy=`, which tunnels
    # https with CONNECT. Plain http goes to the proxy with the absolute URL.
    private def self.execute(uri : URI, proxy : URI?, body : String, headers : HTTP::Headers) : HTTP::Client::Response
      client = HTTP::Client.new(uri)
      begin
        client.connect_timeout = connect_timeout
        client.read_timeout = timeout
        client.write_timeout = timeout
        target = uri.request_target
        if proxy
          client.proxy = HTTP::Proxy::Client.new(proxy.hostname.to_s, proxy.port || 80,
            username: proxy.user.try { |u| URI.decode(u) }, password: proxy.password.try { |p| URI.decode(p) })
          target = uri.to_s if uri.scheme == "http"
        end
        client.post(target, headers: headers, body: body)
      ensure
        client.close
      end
    end
  end
end
