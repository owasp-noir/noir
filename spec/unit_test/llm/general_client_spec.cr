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

# Answers like a provider that rejects some requests: records each request
# body and lets the spec decide the reply.
private class RejectingProvider
  getter bodies = [] of JSON::Any

  def initialize(&@reply : JSON::Any -> {Int32, String})
    @server = HTTP::Server.new do |ctx|
      body = JSON.parse(ctx.request.body.try(&.gets_to_end) || "{}")
      @bodies << body
      status, text = @reply.call(body)
      ctx.response.status_code = status
      ctx.response.print text
    end
    @address = @server.bind_tcp("127.0.0.1", 0)
    spawn { @server.listen }
    Fiber.yield
  end

  def url : String
    "http://#{@address.address}:#{@address.port}/v1"
  end

  def close
    @server.close
  end
end

private OK_REPLY = %({"choices":[{"message":{"content":"{\\"endpoints\\":[]}"}}]})

describe "LLM::General recovering from a rejection" do
  it "drops a temperature the model refuses and keeps it dropped" do
    provider = RejectingProvider.new do |body|
      if body["temperature"]?
        {400, %({"error":{"message":"Unsupported value: 'temperature' does not support 0.3 with this model.","param":"temperature","code":"unsupported_value"}})}
      else
        {200, OK_REPLY}
      end
    end
    begin
      client = LLM::General.new(provider.url, "some-future-reasoner", "k")
      client.request_messages([{"role" => "user", "content" => "x"}]).should eq(%({"endpoints":[]}))
      client.request_messages([{"role" => "user", "content" => "y"}]).should eq(%({"endpoints":[]}))
      provider.bodies.map(&.["temperature"]?.nil?).should eq([false, true, true])
    ensure
      provider.close
    end
  end

  it "sends --ai-temperature and --ai-seed, and no seed by default" do
    provider = RejectingProvider.new { |_| {200, OK_REPLY} }
    begin
      client = LLM::General.new(provider.url, "gpt-4o", "k")
      client.request_messages([{"role" => "user", "content" => "x"}])
      LLM::Sampling.temperature = 0.0
      LLM::Sampling.seed = 42_i64
      client.request_messages([{"role" => "user", "content" => "y"}])
      provider.bodies[0]["temperature"].as_f.should eq(0.3)
      provider.bodies[0]["seed"]?.should be_nil
      provider.bodies[1]["temperature"].as_f.should eq(0.0)
      provider.bodies[1]["seed"].as_i64.should eq(42)
    ensure
      LLM::Sampling.temperature = nil
      LLM::Sampling.seed = nil
      provider.close
    end
  end

  it "raises ContextOverflow only for a caller that can re-split" do
    provider = RejectingProvider.new do |_|
      {400, %({"error":{"message":"This model's maximum context length is 128000 tokens. However, your messages resulted in 130000 tokens.","code":"context_length_exceeded"}})}
    end
    begin
      client = LLM::General.new(provider.url, "gpt-4o", "k")
      messages = [{"role" => "user", "content" => "x"}]
      ex = expect_raises(LLM::ContextOverflow) { client.request_messages(messages, raise_overflow: true) }
      ex.limit.should eq(128000)
      ex.used.should eq(130000)
      expect_raises(LLM::ContextOverflow) { LLM::GeneralAdapter.new(client).request_bundle("s", "u", "json") }
      # Every other caller keeps the "" contract.
      client.request_messages(messages).should eq("")
      LLM::GeneralAdapter.new(client).request_messages(messages).should eq("")
    ensure
      provider.close
    end
  end
end

private def overflow(status : Int32, body : String)
  LLM::General.context_overflow(LLM::HttpTransport::Rejection.new(status, body))
end

describe "LLM::General.context_overflow" do
  {
    "openai"    => { %({"error":{"message":"This model's maximum context length is 8192 tokens. However, your messages resulted in 9000 tokens.","code":"context_length_exceeded"}}), 8192, 9000 },
    "gpt-5"     => { %({"error":{"message":"Input tokens exceed the configured limit of 272000 tokens."}}), 272000, nil },
    "anthropic" => { %({"type":"error","error":{"type":"invalid_request_error","message":"prompt is too long: 250000 tokens > 200000 maximum"}}), 200000, 250000 },
    "gemini"    => { %([{"error":{"code":400,"message":"The input token count (40000) exceeds the maximum number of tokens allowed (32768).","status":"INVALID_ARGUMENT"}}]), 32768, 40000 },
    "lmstudio"  => { %({"error":"The model is loaded with context length of only 4096 tokens"}), 4096, nil },
    "unnamed"   => { %({"error":{"message":"context_length_exceeded"}}), nil, nil },
  }.each do |label, (body, limit, used)|
    it "reads the #{label} overflow" do
      ex = overflow(400, body).should_not be_nil
      ex.limit.should eq(limit)
      ex.used.should eq(used)
    end
  end

  it "takes a bare 413 from a proxy as an overflow" do
    overflow(413, "<html><body>413 Request Entity Too Large</body></html>").should_not be_nil
  end

  it "ignores other rejections" do
    overflow(400, %({"error":{"message":"invalid model"}})).should be_nil
    overflow(401, %({"error":{"message":"context length"}})).should be_nil
  end
end

describe "LLM::General.temperature_rejected?" do
  it "reads the error, not an echo of the request" do
    rejected = ->(body : String) { LLM::General.temperature_rejected?(LLM::HttpTransport::Rejection.new(400, body)) }
    rejected.call(%({"error":{"message":"Unsupported value","param":"temperature","code":"unsupported_value"}})).should be_true
    rejected.call(%({"type":"error","error":{"type":"invalid_request_error","message":"`temperature` is deprecated for this model."}})).should be_true
    rejected.call(%({"error":{"message":"invalid model"},"request":{"temperature":0.3}})).should be_false
  end
end

private SCHEMA_FORMAT = %({"type":"json_schema","json_schema":{"name":"x","schema":{"type":"object"}}})

describe "LLM::General falling back from a rejected response_format" do
  it "steps json_schema down to json_object, then to none, and remembers it" do
    provider = RejectingProvider.new do |body|
      if body["response_format"]?
        {400, %({"error":{"message":"This response_format type is unavailable now"}})}
      else
        {200, OK_REPLY}
      end
    end
    begin
      client = LLM::General.new(provider.url, "gpt-4o", "k")
      messages = [{"role" => "user", "content" => "x"}]
      client.request_messages(messages, SCHEMA_FORMAT).should eq(%({"endpoints":[]}))
      client.request_messages(messages, SCHEMA_FORMAT).should eq(%({"endpoints":[]}))
      provider.bodies.map(&.["response_format"]?.try(&.["type"].as_s)).should eq(["json_schema", "json_object", nil, nil])
    ensure
      provider.close
    end
  end

  it "stops at json_object when the server accepts it" do
    provider = RejectingProvider.new do |body|
      if body["response_format"]?.try(&.["type"]) == "json_schema"
        {400, %({"error":{"message":"json_schema is not supported","param":"response_format"}})}
      else
        {200, OK_REPLY}
      end
    end
    begin
      client = LLM::General.new(provider.url, "gpt-4o", "k")
      client.request_messages([{"role" => "user", "content" => "x"}], SCHEMA_FORMAT).should eq(%({"endpoints":[]}))
      client.request_messages([{"role" => "user", "content" => "y"}], SCHEMA_FORMAT).should eq(%({"endpoints":[]}))
      provider.bodies.map(&.["response_format"]["type"].as_s).should eq(["json_schema", "json_object", "json_object"])
    ensure
      provider.close
    end
  end
end

describe "LLM::General stopping after repeated fatal failures" do
  it "stops sending after three 401s in a row" do
    provider = RejectingProvider.new { |_| {401, %({"error":{"message":"Incorrect API key provided"}})} }
    begin
      client = LLM::General.new(provider.url, "gpt-4o", "bad")
      5.times { client.request_messages([{"role" => "user", "content" => "x"}]).should eq("") }
      provider.bodies.size.should eq(LLM::General::MAX_FATAL_STREAK)
    ensure
      provider.close
    end
  end

  it "resets the streak on a success" do
    count = 0
    provider = RejectingProvider.new do |_|
      count += 1
      count.even? ? {200, OK_REPLY} : {404, %({"error":{"message":"model not found"}})}
    end
    begin
      client = LLM::General.new(provider.url, "gpt-4o", "k")
      6.times { client.request_messages([{"role" => "user", "content" => "x"}]) }
      provider.bodies.size.should eq(6)
    ensure
      provider.close
    end
  end
end

describe "LLM::General reading an unusable reply" do
  it "returns nothing for a refusal or an empty reply, and keeps a truncated one" do
    {
      %({"message":{"content":null,"refusal":"I can't help with that."},"finish_reason":"stop"})   => "",
      %({"message":{"content":""},"finish_reason":"stop"})                                         => "",
      %({"message":{"content":null},"finish_reason":"content_filter"})                             => "",
      %({"message":{"content":"{\\"endpoints\\":[{\\"url\\":\\"/a\\"}"},"finish_reason":"length"}) => %({"endpoints":[{"url":"/a"}),
    }.each do |choice, expected|
      provider = RejectingProvider.new { |_| {200, %({"choices":[#{choice}]})} }
      begin
        LLM::General.new(provider.url, "gpt-4o", "k").request_messages([{"role" => "user", "content" => "x"}]).should eq(expected)
      ensure
        provider.close
      end
    end
  end
end

describe "LLM.unfinished_reply" do
  it "names a truncation, a content filter and an empty reply" do
    LLM.unfinished_reply("length", %({"endpoints":[)).to_s.should contain("truncated by the model's output limit")
    LLM.unfinished_reply("content_filter", "").to_s.should contain("content filter")
    LLM.unfinished_reply("stop", " ").should eq("AI provider returned an empty reply (finish reason: stop)")
    LLM.unfinished_reply(nil, "").should eq("AI provider returned an empty reply")
  end

  it "says nothing about a normal reply" do
    LLM.unfinished_reply("stop", %({"endpoints":[]})).should be_nil
    LLM.unfinished_reply(nil, %({"endpoints":[]})).should be_nil
  end
end
