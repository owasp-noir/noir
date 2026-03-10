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

    it "appends /chat/completions to bare server URL" do
      client = LLM::General.new("http://host.docker.internal:11434/", "test-model", nil)
      client.__test_api.should eq("http://host.docker.internal:11434/chat/completions")
    end

    it "appends /chat/completions to bare server URL without trailing slash" do
      client = LLM::General.new("http://host.docker.internal:11434", "test-model", nil)
      client.__test_api.should eq("http://host.docker.internal:11434/chat/completions")
    end

    it "preserves URL that already ends with /chat/completions" do
      client = LLM::General.new("http://localhost:9999/v1/chat/completions", "test-model", nil)
      client.__test_api.should eq("http://localhost:9999/v1/chat/completions")
    end

    it "appends /chat/completions to custom path" do
      client = LLM::General.new("http://custom-server.com/api/v1", "test-model", nil)
      client.__test_api.should eq("http://custom-server.com/api/v1/chat/completions")
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
end

describe LLM::GeneralAdapter do
  it "supports native tool-calling" do
    adapter = LLM::GeneralAdapter.new(LLM::General.new("http://localhost:9999/v1/chat/completions", "test-model", "test-key"))
    adapter.supports_native_tool_calling?.should be_true
  end
end
