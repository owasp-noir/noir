require "spec"
require "../../../src/llm/ollama/ollama"
require "../../../src/llm/prompt"

# Expose the request URL and body builder so the wire shape can be
# asserted without a live `ollama serve`.
class LLM::Ollama
  def __test_api : String
    @api
  end

  def __test_body(prompt : String, format : String, context : Array(Int32)? = nil) : String
    build_body(prompt, format, context)
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

    it "omits context unless one is being reused" do
      JSON.parse(client.__test_body("hello", "json"))["context"]?.should be_nil
      body = JSON.parse(client.__test_body("hello", "json", [1, 2, 3]))
      body["context"].as_a.map(&.as_i).should eq([1, 2, 3])
    end
  end

  describe "endpoint URL" do
    it "does not double the separator on a trailing-slash base URL" do
      LLM::Ollama.new("http://localhost:11434/", "llama3").__test_api
        .should eq("http://localhost:11434/api/generate")
    end
  end
end
