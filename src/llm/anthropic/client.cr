require "json"
require "../general/client"

module LLM
  # Anthropic's native Messages API (`POST /v1/messages`).
  #
  # Anthropic's OpenAI-compatible endpoint ignores `response_format`, so the
  # endpoint schema the analyzer asks for never reached Claude. This client
  # sends it as `output_config.format` instead, and reads Claude's own reply
  # shape (content blocks, `stop_reason`). Retries, the sampling and
  # structured-output fallbacks and the fail-fast streak are `General`'s.
  class Anthropic < General
    API_VERSION = "2023-06-01"

    # `max_tokens` is required here. Adaptive thinking spends from the same
    # budget, and a reply cut at it is reported like any other truncation.
    # ponytail: fixed; make it a flag if 16k proves short for big bundles.
    MAX_OUTPUT_TOKENS = 16_000

    # Claude 3 and 3.5 reject a `max_tokens` over their smaller output cap
    # with a 400 nothing recovers from, so every request would fail.
    def self.max_output_tokens(model : String) : Int32
      case LLM.model_basename(model)
      when /\Aclaude-3-(?:opus|sonnet|haiku)/ then 4_096
      when /\Aclaude-3-5-/                    then 8_192
      else                                         MAX_OUTPUT_TOKENS
      end
    end

    alias Body = Hash(String, JSON::Any | String | Int32 | Float64 | Array(Hash(String, String)))

    def initialize(url : String, model : String, api_key : String?)
      super
      @api_key ||= ENV["ANTHROPIC_API_KEY"]?.presence
    end

    # `https://api.anthropic.com` and `.../v1` both mean the Messages
    # endpoint under them.
    def self.api_url(url : String) : String
      uri = URI.parse(url)
      path = uri.path.chomp("/")
      unless path.ends_with?("/messages")
        path = path.ends_with?("/v1") ? "#{path}/messages" : "#{path}/v1/messages"
      end
      uri.path = path
      uri.to_s
    end

    def request_messages(messages : Array(Hash(String, String)), format : String = "json", raise_overflow : Bool = false)
      body = message_body(messages, LLM::Sampling.temperature || 0.3)
      # Same unwrap Ollama needs: the analyzer's formats are OpenAI
      # envelopes, and plain JSON mode has no Anthropic equivalent (the
      # prompt already asks for JSON only).
      schema = LLM::Ollama.format_value(format)
      if schema.as_h?
        body["output_config"] = JSON::Any.new({"format" => JSON::Any.new({"type" => JSON::Any.new("json_schema"), "schema" => schema})})
      end

      raw = post(body, raise_overflow)
      return "" if raw.nil?
      self.class.reply_text(JSON.parse(raw))
    rescue e : ContextOverflow
      raise e
    rescue e : Exception
      STDERR.puts "WARNING: AI API error (#{e.message})"
      ""
    end

    def request_messages_with_tools(messages : Array(Hash(String, String)), tools : String)
      body = message_body(messages, LLM::Sampling.temperature || 0.0)
      body["tools"] = self.class.tools(tools)
      body["tool_choice"] = JSON.parse(%({"type":"auto"}))

      raw = post(body)
      return "" if raw.nil?
      self.class.extract_agent_action(JSON.parse(raw))
    rescue e : Exception
      STDERR.puts "WARNING: AI API error (#{e.message})"
      ""
    end

    # System messages go in the top-level `system` field; the API merges
    # consecutive turns of the same role itself.
    private def message_body(messages : Array(Hash(String, String)), temperature : Float64) : Body
      systems = messages.select { |m| m["role"]? == "system" }.compact_map(&.["content"]?)
      turns = messages.reject { |m| m["role"]? == "system" }
      body = Body{"model" => @model, "max_tokens" => self.class.max_output_tokens(@model), "messages" => turns, "temperature" => temperature}
      body["system"] = systems.join("\n\n") unless systems.empty?
      body
    end

    # The text of a reply, or "" for a refusal. Thinking and other non-text
    # blocks are skipped.
    def self.reply_text(response : JSON::Any) : String
      stop = response["stop_reason"]?.try(&.as_s?)
      if stop == "refusal"
        reason = response["stop_details"]?.try(&.["explanation"]?).try(&.as_s?) || "no explanation given"
        STDERR.puts "WARNING: AI model refused the request: #{LLM::HttpTransport.truncate_error_snippet(reason)}"
        return ""
      end

      text = String.build do |io|
        response["content"].as_a.each { |block| io << block["text"].as_s if block["type"]? == "text" }
      end
      LLM.unfinished_reply(stop, text).try { |warning| STDERR.puts "WARNING: #{warning}" }
      LLM.strip_json_fences(text)
    end

    # The first `tool_use` block as the agent's action payload, else the
    # reply's text.
    def self.extract_agent_action(response : JSON::Any) : String
      if call = response["content"].as_a.find { |block| block["type"]? == "tool_use" }
        return build_action_payload(call["name"].as_s, call["input"]? || JSON.parse("{}"))
      end
      reply_text(response)
    rescue Exception
      ""
    end

    # OpenAI `{"type":"function","function":{...}}` tool definitions as
    # Anthropic's `{name, description, input_schema}`.
    def self.tools(openai_tools : String) : JSON::Any
      converted = parse_tools_cached(openai_tools).as_a.map do |tool|
        function = tool["function"]? || tool
        JSON::Any.new({
          "name"         => function["name"],
          "description"  => function["description"]? || JSON::Any.new(""),
          "input_schema" => function["parameters"]? || JSON.parse(%({"type":"object"})),
        })
      end
      JSON::Any.new(converted)
    end

    private def format_key : String
      "output_config"
    end

    private def request_headers : HTTP::Headers
      headers = HTTP::Headers{"Content-Type" => "application/json", "anthropic-version" => API_VERSION}
      @api_key.try { |key| headers["x-api-key"] = key }
      headers
    end
  end
end
