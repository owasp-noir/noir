require "spec"
require "../../../src/llm/general/client"
require "../../../src/llm/adapter"

class LLM::General
  def self.__test_parse_tools_cached(tools : String) : JSON::Any
    parse_tools_cached(tools)
  end

  def self.__test_tools_cache_size : Int32
    @@tools_cache.size
  end

  def __test_api : String
    @api
  end

  def __test_api_key : String?
    @api_key
  end

  def __test_headers : HTTP::Headers
    request_headers
  end

  def __test_encode(body : Hash) : String
    encode(body)
  end
end

private def with_ai_key_env(value : String?, &)
  prev = ENV["NOIR_AI_KEY"]?
  if value
    ENV["NOIR_AI_KEY"] = value
  else
    ENV.delete("NOIR_AI_KEY")
  end
  begin
    yield
  ensure
    if prev
      ENV["NOIR_AI_KEY"] = prev
    else
      ENV.delete("NOIR_AI_KEY")
    end
  end
end

private def build_tool_response(action : String, arguments_raw : String) : JSON::Any
  encoded_arguments = arguments_raw.to_json
  JSON.parse(<<-JSON)
    {
      "choices": [
        {
          "message": {
            "tool_calls": [
              {
                "function": {
                  "name": "#{action}",
                  "arguments": #{encoded_arguments}
                }
              }
            ]
          }
        }
      ]
    }
    JSON
end

private def build_content_response(content_raw : String) : JSON::Any
  encoded_content = content_raw.to_json
  JSON.parse(<<-JSON)
    {
      "choices": [
        {
          "message": {
            "content": #{encoded_content}
          }
        }
      ]
    }
    JSON
end

describe LLM::General do
  describe ".extract_agent_action" do
    it "converts native tool_calls into normalized action payload" do
      response = build_tool_response("grep", %({"pattern":"route"}))

      action_payload = LLM::General.extract_agent_action(response)
      parsed = JSON.parse(action_payload)
      parsed["action"].as_s.should eq("grep")
      parsed["args"]["pattern"].as_s.should eq("route")
    end

    it "keeps textual content when tool_calls are not present" do
      response = build_content_response(%({"action":"finalize","args":{"endpoints":[]}}))

      action_payload = LLM::General.extract_agent_action(response)
      parsed = JSON.parse(action_payload)
      parsed["action"].as_s.should eq("finalize")
    end

    it "uses the content when tool_calls is null" do
      response = JSON.parse(%({"choices":[{"message":{"content":"{\\"action\\":\\"finalize\\"}","tool_calls":null}}]}))

      JSON.parse(LLM::General.extract_agent_action(response))["action"].as_s.should eq("finalize")
    end

    it "accepts tool arguments sent as a JSON object, and null ones" do
      object_args = JSON.parse(%({"choices":[{"message":{"tool_calls":[{"function":{"name":"grep","arguments":{"pattern":"route"}}}]}}]}))
      JSON.parse(LLM::General.extract_agent_action(object_args))["args"]["pattern"].as_s.should eq("route")

      null_args = JSON.parse(%({"choices":[{"message":{"tool_calls":[{"function":{"name":"grep","arguments":null}}]}}]}))
      JSON.parse(LLM::General.extract_agent_action(null_args))["args"].as_h.should be_empty
    end

    it "wraps malformed tool arguments as raw string" do
      response = build_tool_response("read_file", "{not-json")

      action_payload = LLM::General.extract_agent_action(response)
      parsed = JSON.parse(action_payload)
      parsed["action"].as_s.should eq("read_file")
      parsed["args"]["raw"].as_s.should eq("{not-json")
    end
  end

  describe ".parse_tools_cached (test hook)" do
    it "reuses parsed schema for the same tools payload" do
      unique_tools = <<-JSON
        [
          {
            "type": "function",
            "function": {
              "name": "cache_probe_tool",
              "parameters": {"type": "object", "properties": {}, "additionalProperties": false}
            }
          }
        ]
        JSON

      size_before = LLM::General.__test_tools_cache_size
      first = LLM::General.__test_parse_tools_cached(unique_tools)
      size_after_first = LLM::General.__test_tools_cache_size
      second = LLM::General.__test_parse_tools_cached(unique_tools)
      size_after_second = LLM::General.__test_tools_cache_size

      first.as_a[0]["function"]["name"].as_s.should eq("cache_probe_tool")
      second.as_a[0]["function"]["name"].as_s.should eq("cache_probe_tool")
      size_after_first.should eq(size_before + 1)
      size_after_second.should eq(size_after_first)
    end
  end

  describe "URL normalization" do
    it "appends /chat/completions to base URL with /v1 path" do
      client = LLM::General.new("http://localhost:11434/v1", "test-model", nil)
      client.__test_api.should eq("http://localhost:11434/v1/chat/completions")
    end

    it "appends /v1/chat/completions to bare server URL" do
      client = LLM::General.new("http://host.docker.internal:11434/", "test-model", nil)
      client.__test_api.should eq("http://host.docker.internal:11434/v1/chat/completions")
    end

    it "appends /v1/chat/completions to bare server URL without trailing slash" do
      client = LLM::General.new("http://host.docker.internal:11434", "test-model", nil)
      client.__test_api.should eq("http://host.docker.internal:11434/v1/chat/completions")
    end

    it "preserves URL that already ends with /chat/completions" do
      client = LLM::General.new("http://localhost:9999/v1/chat/completions", "test-model", nil)
      client.__test_api.should eq("http://localhost:9999/v1/chat/completions")
    end

    it "appends /chat/completions to custom path" do
      client = LLM::General.new("http://custom-server.com/api/v1", "test-model", nil)
      client.__test_api.should eq("http://custom-server.com/api/v1/chat/completions")
    end

    it "keeps a query string after the path instead of appending to it" do
      azure = "https://r.openai.azure.com/openai/deployments/gpt4/chat/completions?api-version=2024-02-01"
      LLM::General.new(azure, "m", nil).__test_api.should eq(azure)
      LLM::General.new("https://r.openai.azure.com/openai/deployments/gpt4?api-version=2024-02-01", "m", nil).__test_api
        .should eq(azure)
      LLM::General.new("http://127.0.0.1:8080/?key=1", "m", nil).__test_api
        .should eq("http://127.0.0.1:8080/v1/chat/completions?key=1")
    end

    it "resolves prefix 'openai' to full endpoint URL" do
      client = LLM::General.new("openai", "test-model", "test-key")
      client.__test_api.should eq("https://api.openai.com/v1/chat/completions")
    end

    it "resolves prefix 'ollama' to full endpoint URL" do
      client = LLM::General.new("ollama", "test-model", nil)
      client.__test_api.should eq("http://localhost:11434/v1/chat/completions")
    end
  end

  describe "API key resolution" do
    it "sends a bearer token when a key is configured" do
      client = LLM::General.new("openai", "test-model", "sk-test")
      client.__test_headers["Authorization"].should eq("Bearer sk-test")
    end

    it "omits Authorization entirely for keyless local providers" do
      # `Authorization: Bearer ` is worse than no header: a keyless
      # provider rejects it instead of serving the request anonymously.
      with_ai_key_env(nil) do
        client = LLM::General.new("ollama", "test-model", "")
        client.__test_api_key.should be_nil
        client.__test_headers["Authorization"]?.should be_nil
      end
    end

    it "falls back to NOIR_AI_KEY when the configured key is empty" do
      with_ai_key_env("env-key") do
        LLM::General.new("openai", "test-model", "").__test_api_key.should eq("env-key")
        LLM::General.new("openai", "test-model", nil).__test_api_key.should eq("env-key")
      end
    end

    it "prefers an explicit key over the environment" do
      with_ai_key_env("env-key") do
        LLM::General.new("openai", "test-model", "sk-explicit").__test_api_key.should eq("sk-explicit")
      end
    end
  end
end

describe LLM::GeneralAdapter do
  it "supports native tool-calling" do
    adapter = LLM::GeneralAdapter.new(LLM::General.new("http://localhost:9999/v1/chat/completions", "test-model", "test-key"))
    adapter.supports_native_tool_calling?.should be_true
  end
end

describe "LLM::General.sampling_temperature?" do
  it "omits temperature for models that reject a non-default value" do
    %w[o1 o3-mini o4-mini-2025-04-16 gpt-5 gpt-5.4-mini claude-opus-4-7 claude-opus-5-5
      claude-sonnet-5 claude-sonnet-5-5 claude-haiku-5-5 claude-fable-5-1 claude-mythos-5
      anthropic/claude-opus-4-8 openai/gpt-5].each do |model|
      LLM::General.sampling_temperature?(model).should be_false
    end
  end

  it "keeps temperature for models that accept it" do
    %w[gpt-4o gpt-4.1 claude-opus-4-6 claude-sonnet-4-6 claude-haiku-4-5 claude-3-5-sonnet
      gemini-3-pro llama3.1:8b olmo2 grok-4 gpt-oss-20b].each do |model|
      LLM::General.sampling_temperature?(model).should be_true
    end
  end
end

describe "LLM::General request body" do
  it "drops temperature for a model that rejects it and keeps it otherwise" do
    body = {"model" => "x", "temperature" => 0.3}
    JSON.parse(LLM::General.new("openai", "o3", "k").__test_encode(body.dup))["temperature"]?.should be_nil
    JSON.parse(LLM::General.new("openai", "gpt-4o", "k").__test_encode(body.dup))["temperature"].as_f.should eq(0.3)
  end
end
