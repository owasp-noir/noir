require "spec"
require "http/server"
require "../../../src/llm/ollama/ollama"
require "../../../src/llm/prompt"

# Expose the request URL and body builder so the wire shape can be
# asserted without a live `ollama serve`.
class LLM::Ollama
  def __test_api : String
    @api
  end

  def __test_body(prompt : String, format : String) : String
    build_body(prompt, format)
  end
end

# A local stand-in for `ollama serve` that records each request and
# answers with a reply that carries a KV `context`.
private class FakeOllama
  getter bodies = [] of JSON::Any
  getter auth = [] of String?

  def initialize
    @server = HTTP::Server.new do |ctx|
      @bodies << JSON.parse(ctx.request.body.try(&.gets_to_end) || "{}")
      @auth << ctx.request.headers["Authorization"]?
      ctx.response.print %({"response":"{}","context":[1,2,3]})
    end
    @address = @server.bind_tcp("127.0.0.1", 0)
    spawn { @server.listen }
    Fiber.yield
  end

  def url : String
    "http://#{@address.address}:#{@address.port}"
  end

  def close
    @server.close
  end
end

private def with_ai_key_env(value : String?, &)
  prev = ENV["NOIR_AI_KEY"]?
  value ? (ENV["NOIR_AI_KEY"] = value) : ENV.delete("NOIR_AI_KEY")
  begin
    yield
  ensure
    prev ? (ENV["NOIR_AI_KEY"] = prev) : ENV.delete("NOIR_AI_KEY")
  end
end

describe LLM::Ollama do
  describe ".format_value" do
    it "maps plain json mode to the literal string" do
      LLM::Ollama.format_value("json").as_s.should eq("json")
      LLM::Ollama.format_value("").as_s.should eq("json")
    end

    it "unwraps an OpenAI-shaped json_schema envelope to the inner schema" do
      value = LLM::Ollama.format_value(LLM::ANALYZE_FORMAT)
      # Ollama constrains decoding with this schema, so it has to describe
      # the endpoints object — not the envelope that wraps it.
      value["type"].as_s.should eq("object")
      value["properties"]["endpoints"].should_not be_nil
    end

    it "passes a bare JSON Schema through unchanged" do
      schema = %({"type":"object","properties":{"files":{"type":"array"}}})
      value = LLM::Ollama.format_value(schema)
      value["properties"]["files"]["type"].as_s.should eq("array")
    end

    it "falls back to json mode for an envelope it cannot unwrap" do
      LLM::Ollama.format_value(%({"type":"json_schema"})).as_s.should eq("json")
      LLM::Ollama.format_value("not json at all").as_s.should eq("json")
      LLM::Ollama.format_value("[1,2,3]").as_s.should eq("json")
    end
  end

  describe "request body" do
    client = LLM::Ollama.new("http://localhost:11434", "llama3")

    it "sends temperature under options where Ollama reads it" do
      body = JSON.parse(client.__test_body("hello", "json"))
      body["options"]["temperature"].as_f.should eq(LLM::Ollama::TEMPERATURE)
      # A top-level temperature is silently discarded by the API.
      body["temperature"]?.should be_nil
    end

    it "sends --ai-temperature and --ai-seed under options" do
      LLM::Sampling.temperature = 0.0
      LLM::Sampling.seed = 7_i64
      options = JSON.parse(client.__test_body("hello", "json"))["options"]
      options["temperature"].as_f.should eq(0.0)
      options["seed"].as_i64.should eq(7)
    ensure
      LLM::Sampling.temperature = nil
      LLM::Sampling.seed = nil
    end

    it "sizes num_ctx to the caller's token budget, rounded up to 1024" do
      # Without it Ollama runs at its 2-4k default and silently truncates
      # a bundle sized for the model's full window.
      sized = LLM::Ollama.new("http://localhost:11434", "llama3.1", 128_000)
      JSON.parse(sized.__test_body("hi", "json"))["options"]["num_ctx"].as_i.should eq(128_000)
      odd = LLM::Ollama.new("http://localhost:11434", "llama3", 4000)
      JSON.parse(odd.__test_body("hi", "json"))["options"]["num_ctx"].as_i.should eq(4096)
      JSON.parse(client.__test_body("hi", "json"))["options"]["num_ctx"]?.should be_nil
    end

    it "carries the model, prompt and non-streaming flag" do
      body = JSON.parse(client.__test_body("hello", "json"))
      body["model"].as_s.should eq("llama3")
      body["prompt"].as_s.should eq("hello")
      body["stream"].as_bool.should be_false
    end

    it "sends the unwrapped schema as format" do
      body = JSON.parse(client.__test_body("hello", LLM::ANALYZE_FORMAT))
      body["format"]["type"].as_s.should eq("object")
    end
  end

  describe "requests" do
    it "does not chain the KV context between independent requests" do
      # Feeding file N's context into file N+1 made each answer depend on
      # which files were analyzed before it.
      server = FakeOllama.new
      begin
        ollama = LLM::Ollama.new(server.url, "llama3")
        ollama.request_with_context("sys", "file a", "json").should eq("{}")
        ollama.request_with_context("sys", "file b", "json").should eq("{}")
        server.bodies.size.should eq(2)
        server.bodies.each(&.["context"]?.should(be_nil))
      ensure
        server.close
      end
    end

    it "sends the API key as a bearer token, falling back to NOIR_AI_KEY" do
      server = FakeOllama.new
      begin
        with_ai_key_env("env-key") do
          LLM::Ollama.new(server.url, "llama3", nil, "cli-key").request("p")
          LLM::Ollama.new(server.url, "llama3", nil, "").request("p")
        end
        with_ai_key_env(nil) do
          LLM::Ollama.new(server.url, "llama3").request("p")
        end
        server.auth.should eq(["Bearer cli-key", "Bearer env-key", nil])
      ensure
        server.close
      end
    end
  end

  describe "endpoint URL" do
    it "does not double the separator on a trailing-slash base URL" do
      LLM::Ollama.new("http://localhost:11434/", "llama3").__test_api
        .should eq("http://localhost:11434/api/generate")
    end
  end
end
