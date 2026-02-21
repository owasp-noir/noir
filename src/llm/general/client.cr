require "json"
require "http/client"

module LLM
  # General OpenAI-compatible LLM client
  class General
    @@tools_cache = {} of String => JSON::Any
    @@tools_cache_mutex = Mutex.new

    def initialize(url : String, model : String, api_key : String?)
      @url = url
      @api = if url.includes?("://")
               url
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
      @api_key = api_key || ENV["NOIR_AI_KEY"]?
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

      headers = HTTP::Headers.new
      headers["Content-Type"] = "application/json"
      headers["Authorization"] = "Bearer #{@api_key}" if @api_key

      response = HTTP::Client.post(@api, headers: headers, body: body)
      unless response.success?
        snippet = response.body.size > 1024 ? "#{response.body[0, 1024]}..." : response.body
        STDERR.puts "WARNING: AI API error (HTTP #{response.status_code}): #{snippet}"
        return ""
      end
      response_json = JSON.parse(response.body)

      response_json["choices"][0]["message"]["content"].to_s.gsub("```json", "").gsub("```", "").strip
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

      headers = HTTP::Headers.new
      headers["Content-Type"] = "application/json"
      headers["Authorization"] = "Bearer #{@api_key}" if @api_key

      response = HTTP::Client.post(@api, headers: headers, body: body)
      unless response.success?
        snippet = response.body.size > 1024 ? "#{response.body[0, 1024]}..." : response.body
        STDERR.puts "WARNING: AI API error (HTTP #{response.status_code}): #{snippet}"
        return ""
      end

      response_json = JSON.parse(response.body)
      self.class.extract_agent_action(response_json)
    rescue e : Exception
      STDERR.puts "WARNING: AI API error (#{e.message})"
      ""
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
      text.gsub("```json", "").gsub("```", "").strip
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
