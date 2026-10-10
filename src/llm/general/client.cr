require "json"
require "uri"
require "http/client"
require "../response_cleanup"
require "../http_transport"
require "../prompt"

module LLM
  # A request whose prompt is over the model's context window, raised for a
  # caller that asked to re-split instead of getting "". `limit` is the
  # window and `used` the prompt's real size, when the provider named them.
  class ContextOverflow < Exception
    getter limit : Int32?
    getter used : Int32?

    def initialize(@limit : Int32? = nil, @used : Int32? = nil)
      super("prompt exceeds the model's context window#{" (#{@used} > #{@limit} tokens)" if @limit && @used}")
    end
  end

  # General OpenAI-compatible LLM client
  class General
    @@tools_cache = {} of String => JSON::Any
    @@tools_cache_mutex = Mutex.new

    @api_key : String?
    @send_temperature : Bool

    # How much of `response_format` the server accepts, learned from its
    # 400s and kept for the rest of the run. Ordered: each step only drops.
    enum ResponseFormat
      AsAsked
      JsonObject
      Omitted
    end

    JSON_OBJECT_FORMAT = JSON.parse(%({"type":"json_object"}))

    @response_format = ResponseFormat::AsAsked

    # A bad key, a missing model or an unreachable host fails every request
    # the same way. After this many in a row the client stops sending, so a
    # 1000-file scan does not repeat the same failure 1000 times; the files
    # it skips are reported as unanalyzed by the caller.
    MAX_FATAL_STREAK = 3
    FATAL_STATUS     = Set{401, 403, 404}

    @fatal_streak = Atomic(Int32).new(0)

    def initialize(url : String, model : String, api_key : String?)
      @url = url
      @api = if url.includes?("://")
               self.class.chat_completions_url(url)
             else
               case url.downcase
               when "openai"
                 "https://api.openai.com/v1/chat/completions"
               when "ollama"
                 "http://localhost:11434/v1/chat/completions"
               when "lmstudio"
                 "http://localhost:1234/v1/chat/completions"
               when "xai"
                 "https://api.x.ai/v1/chat/completions"
               when "vllm"
                 "http://localhost:8000/v1/chat/completions"
               when "azure"
                 "https://models.inference.ai.azure.com/chat/completions"
               when "github"
                 "https://models.github.ai/inference/chat/completions"
               when "openrouter"
                 "https://openrouter.ai/api/v1/chat/completions"
               else
                 url
               end
             end

      @model = model
      @send_temperature = self.class.sampling_temperature?(model)
      # An empty key means "no key given", not "authenticate with an empty
      # string". Treating it literally suppressed the documented
      # NOIR_AI_KEY fallback for every caller that passes the config
      # default through, and put a blank bearer token on the wire.
      @api_key = api_key.presence || ENV["NOIR_AI_KEY"]?.presence
    end

    # Parse provider response into normalized JSON action payload.
    # If the model returns tool_calls, convert them to:
    #   {"action":"<function_name>","args":{...}}
    # Otherwise, return cleaned textual content as-is.
    def self.extract_agent_action(response_json : JSON::Any) : String
      message = response_json["choices"][0]["message"]
      # `tool_calls: null` is "no tool call", not an error: `as_a` on it
      # raised and the rescue below turned a usable content reply into "".
      if first_call = message["tool_calls"]?.try(&.as_a?).try(&.first?)
        function = first_call["function"]
        action = function["name"].as_s
        # Some servers send `arguments` as a JSON object rather than the
        # spec's string; `to_s` rendered that as a Crystal inspect string.
        args = function["arguments"]?
        arguments = if args.nil? || args.raw.nil?
                      JSON.parse("{}")
                    elsif text = args.as_s?
                      parse_tool_arguments(text)
                    else
                      args
                    end
        return build_action_payload(action, arguments)
      end

      LLM.strip_json_fences(message["content"]?.try(&.to_s) || "")
    rescue Exception
      ""
    end

    # Reasoning models answer a non-default `temperature` with HTTP 400:
    # OpenAI's o-series and GPT-5 family (its `-chat` models excepted), and
    # Claude from Opus 4.7 / Sonnet 5 / Haiku 5.5 on (Fable and Mythos
    # included). `post` recovers from that rejection for any model, so this
    # list only saves the first wasted request for the models it names.
    FIXED_SAMPLING_MODEL = /\A(?:o\d+(?:-|\z)|gpt-5(?![\w.-]*-chat)|claude-(?:opus-4-[7-9]|(?:opus|sonnet|haiku)-[5-9]|fable|mythos))/

    def self.sampling_temperature?(model : String) : Bool
      !LLM.model_basename(model).matches?(FIXED_SAMPLING_MODEL)
    end

    # The 400 for a rejected sampling parameter: OpenAI names it in `param`
    # (`unsupported_value`), Anthropic in the message. Only the error itself
    # is read; a gateway that echoes the request would otherwise match on
    # every 400.
    def self.temperature_rejected?(rejection : HttpTransport::Rejection) : Bool
      rejected_for?(rejection, /temperature/i)
    end

    # A server that implements only `json_object`, or no structured output
    # at all, answers every `json_schema` request with a 400 naming it.
    def self.response_format_rejected?(rejection : HttpTransport::Rejection) : Bool
      rejected_for?(rejection, /response_format|json_schema|json_object/i)
    end

    private def self.rejected_for?(rejection : HttpTransport::Rejection, pattern : Regex) : Bool
      return false unless rejection.status == 400
      error = JSON.parse(rejection.body).as_h?.try(&.["error"]?)
      text = error.try { |e| e.as_h? ? "#{e["param"]?} #{e["message"]?}" : e.to_s } || rejection.body
      text.matches?(pattern)
    rescue JSON::ParseException
      rejection.body.matches?(pattern)
    end

    CONTEXT_OVERFLOW = /context_length_exceeded|context length|context window|prompt is too long|maximum number of tokens|too many (?:input )?tokens|exceed[s]? the (?:configured )?limit/i

    # How OpenAI, vLLM, Anthropic, Gemini and LM Studio state the window ...
    CONTEXT_LIMIT = [
      /maximum context length is (\d+)/i,
      /> ?(\d+) maximum/i,
      /maximum number of tokens allowed \((\d+)\)/i,
      /context length of only (\d+)/i,
      /limit of (\d+) tokens/i,
    ]

    # ... and the prompt's real size, which corrects noir's chars/4 estimate.
    CONTEXT_USED = [
      /resulted in (\d+) tokens/i,
      /prompt is too long: (\d+) tokens/i,
      /input token count \((\d+)\)/i,
    ]

    # nil when the rejection is not a context overflow. A 413 is one even
    # with no wording: a reverse proxy's body-size cap answers in HTML.
    def self.context_overflow(rejection : HttpTransport::Rejection) : ContextOverflow?
      body = rejection.body
      return unless rejection.status == 413 || (rejection.status == 400 && body.matches?(CONTEXT_OVERFLOW))
      ContextOverflow.new(first_number(body, CONTEXT_LIMIT), first_number(body, CONTEXT_USED))
    end

    private def self.first_number(text : String, patterns : Array(Regex)) : Int32?
      patterns.each do |re|
        if (m = text.match(re)) && (n = m[1].to_i?) && n > 0
          return n
        end
      end
    end

    # Sends a request body, recovering from the rejections a model name
    # cannot predict: a `temperature` the model refuses is dropped for the
    # rest of the run and the request resent, and a refused `json_schema`
    # steps down to `json_object`, then to no `response_format` (the prompt
    # already asks for JSON only). A prompt over the context window raises
    # `ContextOverflow` when the caller can re-split it, and is reported like
    # any other failure when it cannot.
    private def post(body : Hash, raise_overflow : Bool = false) : String?
      return if @fatal_streak.get >= MAX_FATAL_STREAK

      if body.has_key?("response_format")
        case @response_format
        when .json_object? then body["response_format"] = JSON_OBJECT_FORMAT
        when .omitted?     then body.delete("response_format")
        end
      end

      result = LLM::HttpTransport.post_json_result(@api, encode(body), request_headers)
      case result
      when String
        @fatal_streak.set(0)
        return result
      when nil
        # The transport already reported the connection failure.
        count_fatal_failure
        return
      end

      if @send_temperature && self.class.temperature_rejected?(result)
        @send_temperature = false
        return post(body, raise_overflow)
      end

      if (sent = body["response_format"]?) && self.class.response_format_rejected?(result)
        # Stepped from what was sent, not from the current setting: requests
        # in flight concurrently all come back rejected at the old level.
        step = sent.to_json.includes?("json_schema") ? ResponseFormat::JsonObject : ResponseFormat::Omitted
        @response_format = step if step > @response_format
        return post(body, raise_overflow)
      end

      if raise_overflow && (overflow = self.class.context_overflow(result))
        raise overflow
      end
      LLM::HttpTransport.report(result)
      count_fatal_failure if FATAL_STATUS.includes?(result.status)
      nil
    end

    private def count_fatal_failure : Nil
      return unless @fatal_streak.add(1) == MAX_FATAL_STREAK - 1
      STDERR.puts "WARNING: AI provider failed #{MAX_FATAL_STREAK} requests in a row (bad key, unknown model or unreachable host); skipping the remaining AI requests"
    end

    # Make a request with chat-style messages
    # `raise_overflow` turns a context-window rejection into
    # `ContextOverflow` instead of "" (see `post`).
    def request_messages(messages : Array(Hash(String, String)), format : String = "json", raise_overflow : Bool = false)
      body = {
        "model"           => @model,
        "messages"        => messages,
        "temperature"     => 0.3,
        "stream"          => false,
        "response_format" => format == "json" ? {"type" => "json_object"} : JSON.parse(format),
      }

      raw = post(body, raise_overflow)
      return "" if raw.nil?

      response_json = JSON.parse(raw)
      return "" if report_api_error(response_json)

      LLM.strip_json_fences(response_json["choices"][0]["message"]["content"].to_s)
    rescue e : ContextOverflow
      raise e
    rescue e : Exception
      STDERR.puts "WARNING: AI API error (#{e.message})"
      ""
    end

    # Request next action with provider-native tool-calling.
    # `tools` must be a JSON array string compatible with OpenAI-style chat completions API.
    def request_messages_with_tools(messages : Array(Hash(String, String)), tools : String)
      parsed_tools = LLM::General.parse_tools_cached(tools)
      body = {
        "model"       => @model,
        "messages"    => messages,
        "temperature" => 0.0,
        "stream"      => false,
        "tools"       => parsed_tools,
        "tool_choice" => "auto",
      }

      raw = post(body)
      return "" if raw.nil?

      response_json = JSON.parse(raw)
      return "" if report_api_error(response_json)

      self.class.extract_agent_action(response_json)
    rescue e : Exception
      STDERR.puts "WARNING: AI API error (#{e.message})"
      ""
    end

    private def encode(body : Hash) : String
      body.delete("temperature") unless @send_temperature
      body.to_json
    end

    private def request_headers : HTTP::Headers
      headers = HTTP::Headers.new
      headers["Content-Type"] = "application/json"
      # `@api_key` is normalized to nil when absent, so a keyless local
      # provider (ollama, vLLM, LM Studio) is never sent the blank
      # `Authorization: Bearer ` header that made it reject the request.
      if key = @api_key
        headers["Authorization"] = "Bearer #{key}"
      end
      headers
    end

    # Some gateways answer HTTP 200 with `{"error": {...}}` in the body.
    # Without this the response just fails the `choices` lookup below and
    # the caller reports a generic parse error, hiding a message that names
    # the actual problem (unknown model, quota, bad deployment name).
    private def report_api_error(response_json : JSON::Any) : Bool
      error = response_json["error"]?
      return false if error.nil?

      message = error["message"]?.try(&.as_s?) || error.to_s
      STDERR.puts "WARNING: AI API returned an error: #{LLM::HttpTransport.truncate_error_snippet(message)}"
      true
    rescue Exception
      false
    end

    # Make a simple request with a single prompt
    def request(prompt : String, format : String = "json")
      messages = [{"role" => "user", "content" => prompt}]
      request_messages(messages, format).to_s
    end

    private def self.build_action_payload(action : String, args : JSON::Any) : String
      JSON.build do |json|
        json.object do
          json.field "action", action
          json.field "args" do
            args.to_json(json)
          end
        end
      end
    end

    private def self.parse_tool_arguments(raw : String) : JSON::Any
      text = raw.strip
      return JSON.parse("{}") if text.empty?
      JSON.parse(text)
    rescue Exception
      JSON.parse(%({"raw":#{raw.to_json}}))
    end

    # Decided on the URI path, not the whole string: an Azure-style
    # `...?api-version=2024-02-01` query used to get `/chat/completions`
    # appended after it.
    def self.chat_completions_url(url : String) : String
      uri = URI.parse(url)
      path = uri.path.chomp("/")
      unless path.ends_with?("/chat/completions")
        path = path.empty? ? "/v1/chat/completions" : "#{path}/chat/completions"
      end
      uri.path = path
      uri.to_s
    end

    def self.parse_tools_cached(tools : String) : JSON::Any
      return JSON.parse("[]") if tools.empty?

      if cached = @@tools_cache_mutex.synchronize { @@tools_cache[tools]? }
        return cached
      end

      parsed = JSON.parse(tools)
      @@tools_cache_mutex.synchronize do
        @@tools_cache[tools] = parsed
      end
      parsed
    end
  end
end
