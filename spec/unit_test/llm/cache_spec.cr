require "../../../src/llm/cache"
require "spec"

describe LLM::Cache do
  describe ".key" do
    it "generates a deterministic SHA256 hash" do
      provider = "openai"
      model = "gpt-4o"
      kind = "ANALYZE"
      format = "json"
      payload = "some payload"

      # "openai|gpt-4o|ANALYZE|json|some payload"
      expected_hash = "236649cef258475a5d82d8519748c36ab49bf5bdf619c9f7b2e117a575fe08ac"

      key = LLM::Cache.key(provider, model, kind, format, payload)
      key.should eq(expected_hash)
    end

    it "produces different keys for different inputs" do
      k1 = LLM::Cache.key("p1", "m1", "k1", "f1", "payload")
      k2 = LLM::Cache.key("p1", "m1", "k1", "f1", "payload2")
      k1.should_not eq(k2)
    end
  end
end
