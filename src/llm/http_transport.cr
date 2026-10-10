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
    def self.retry_after(response : HTTP::Client::Response?) : Time::Span?
      raw = response.try(&.headers["Retry-After"]?)
      return if raw.nil?
      seconds = raw.strip.to_f?
      return if seconds.nil? || seconds <= 0
      span = seconds.seconds
      span > MAX_RETRY_AFTER ? MAX_RETRY_AFTER : span
    end

    def self.retry_delay(response : HTTP::Client::Response?, attempt : Int32) : Time::Span
      retry_after(response) || backoff(attempt)
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

    def self.redact(text : String) : String
      Noir::Redact.secret(text, @@secrets_mutex.synchronize { @@secrets.dup })
    end

    # Every provider error text that reaches stderr goes through here, so
    # it is also where the key is masked — before the cut, so a key
    # straddling it cannot leak its prefix.
    def self.truncate_error_snippet(body : String) : String
      body = redact(body)
      body.size > MAX_ERROR_SNIPPET_SIZE ? "#{body[0, MAX_ERROR_SNIPPET_SIZE]}..." : body
    end

    # A provider's final answer that was not a success and not worth
    # another attempt (a 400 naming a bad parameter, a prompt over the
    # context window). Handed back so the caller can read why.
    record Rejection, status : Int32, body : String

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
      attempt = 0
      loop do
        attempt += 1
        response = nil
        error = nil

        begin
          response = execute(url, body, headers)
          return response.body if response.success?
        rescue e : IO::Error
          # Connect/read timeouts, refused connections and resets all
          # arrive as IO::Error subclasses.
          error = e
        end

        retryable = !error.nil? || (response && retryable_status?(response.status_code))
        if retryable && attempt < MAX_ATTEMPTS
          sleep retry_delay(response, attempt)
          next
        end

        if error
          STDERR.puts "WARNING: AI API request failed after #{attempt} attempt(s): #{error.class} (#{error.message})"
        elsif response
          return Rejection.new(response.status_code, response.body)
        end
        return
      end
    end

    def self.report(rejection : Rejection) : Nil
      STDERR.puts "WARNING: AI API error (HTTP #{rejection.status}): #{truncate_error_snippet(rejection.body)}"
    end

    private def self.execute(url : String, body : String, headers : HTTP::Headers) : HTTP::Client::Response
      uri = URI.parse(url)
      client = HTTP::Client.new(uri)
      begin
        client.connect_timeout = connect_timeout
        client.read_timeout = timeout
        client.write_timeout = timeout
        client.post(uri.request_target, headers: headers, body: body)
      ensure
        client.close
      end
    end
  end
end
