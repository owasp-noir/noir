require "json"
require "uri"
require "http/client"
require "../response_cleanup"
require "../http_transport"

module LLM
  # General OpenAI-compatible LLM client
  class General
    @@tools_cache = {} of String => JSON::Any
    @@tools_cache_mutex = Mutex.new

    @api_key : String?

    def initialize(url : String, model : String, api_key : String?)
      @url = url
      @api = if url.includes?("://")
               ensure_chat_completions_path(url)
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
      if tool_calls = message["tool_calls"]?
        first_call = tool_calls.as_a.first?
        if first_call
          function = first_call["function"]
          action = function["name"].as_s
          arguments_raw = function["arguments"]?.try(&.to_s) || "{}"
          arguments = parse_tool_arguments(arguments_raw)
          return build_action_payload(action, arguments)
        end
      end

      clean_content(message["content"]?.try(&.to_s) || "")
    rescue Exception
      ""
    end

    # Make a request with chat-style messages
    def request_messages(messages : Array(Hash(String, String)), format : String = "json")
      body = {
        "model"           => @model,
        "messages"        => messages,
        "temperature"     => 0.3,
        "stream"          => false,
        "response_format" => format == "json" ? {"type" => "json_object"} : JSON.parse(format),
      }.to_json

      raw = LLM::HttpTransport.post_json(@api, body, request_headers)
      return "" if raw.nil?

      response_json = JSON.parse(raw)
      return "" if report_api_error(response_json)

      LLM.strip_json_fences(response_json["choices"][0]["message"]["content"].to_s)
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
      }.to_json

      raw = LLM::HttpTransport.post_json(@api, body, request_headers)
      return "" if raw.nil?

      response_json = JSON.parse(raw)
      return "" if report_api_error(response_json)

      self.class.extract_agent_action(response_json)
    rescue e : Exception
      STDERR.puts "WARNING: AI API error (#{e.message})"
      ""
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

    private def self.clean_content(text : String) : String
      LLM.strip_json_fences(text)
    end

    private def ensure_chat_completions_path(url : String) : String
      normalized = url.chomp("/")
      return normalized if normalized.ends_with?("/chat/completions")

      uri = URI.parse(normalized)
      path = uri.path || ""
      if path.empty? || path == "/"
        "#{normalized}/v1/chat/completions"
      else
        "#{normalized}/chat/completions"
      end
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
