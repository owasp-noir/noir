require "../../../../spec_helper"
require "../../../../../src/analyzer/analyzers/llm_analyzers/unified_ai"

# Test hooks for the deterministic FP/FN guards. These run entirely
# offline (no LLM call) and assert that hallucinated URLs/params are
# dropped while legitimate ones survive.
class Analyzer::AI::Unified
  def __test_plausible_url(url : String) : Bool
    plausible_endpoint_url?(url)
  end

  def __test_plausible_param(name : String) : Bool
    plausible_param_name?(name)
  end

  def __test_create_endpoint(json : String) : Endpoint?
    create_endpoint_from_json(JSON.parse(json), "/tmp/ai_detected")
  end
end

private def build_validation_analyzer : Analyzer::AI::Unified
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(".")])
  options["ai_provider"] = YAML::Any.new("openai")
  options["ai_model"] = YAML::Any.new("gpt-4o-mini")
  options["ai_max_token"] = YAML::Any.new(1024)
  Analyzer::AI::Unified.new(options)
end

describe Analyzer::AI::Unified do
  describe "endpoint url plausibility" do
    analyzer = build_validation_analyzer

    it "accepts real request paths" do
      analyzer.__test_plausible_url("/api/v1/users").should be_true
      analyzer.__test_plausible_url("/users/{id}").should be_true
      analyzer.__test_plausible_url("/users/:id").should be_true
      analyzer.__test_plausible_url("/users/<int:id>").should be_true
      analyzer.__test_plausible_url("/").should be_true
      analyzer.__test_plausible_url("https://api.example.com/v1/items").should be_true
    end

    it "rejects URLs that leak whitespace (captured prose or 'METHOD /path')" do
      analyzer.__test_plausible_url("GET /api/users").should be_false
      analyzer.__test_plausible_url("/api/users get all users").should be_false
      analyzer.__test_plausible_url("/api/\nusers").should be_false
      analyzer.__test_plausible_url("/api/\tusers").should be_false
    end

    it "rejects empty and placeholder URLs" do
      analyzer.__test_plausible_url("").should be_false
      analyzer.__test_plausible_url("url").should be_false
      analyzer.__test_plausible_url("/endpoint").should be_false
      analyzer.__test_plausible_url("N/A").should be_false
      analyzer.__test_plausible_url("none").should be_false
      analyzer.__test_plausible_url("path/to/endpoint").should be_false
      analyzer.__test_plausible_url("...").should be_false
    end

    it "rejects markdown/code noise and oversized URLs" do
      analyzer.__test_plausible_url("/api/`users`").should be_false
      analyzer.__test_plausible_url("/#{"a" * 3000}").should be_false
    end
  end

  describe "param name plausibility" do
    analyzer = build_validation_analyzer

    it "accepts identifier-like names" do
      analyzer.__test_plausible_param("id").should be_true
      analyzer.__test_plausible_param("user_id").should be_true
      analyzer.__test_plausible_param("X-Api-Key").should be_true
    end

    it "rejects names with whitespace or that are oversized" do
      analyzer.__test_plausible_param("").should be_false
      analyzer.__test_plausible_param("the user id").should be_false
      analyzer.__test_plausible_param("a\tb").should be_false
      analyzer.__test_plausible_param("x" * 200).should be_false
    end
  end

  describe "create_endpoint_from_json" do
    analyzer = build_validation_analyzer

    it "builds a valid endpoint and drops garbage params" do
      ep = analyzer.__test_create_endpoint(
        %({"url":"/api/items","method":"post","params":[{"name":"q","param_type":"query","value":""},{"name":"bad name","param_type":"query","value":""}]})
      )
      ep = ep.should_not be_nil
      ep.url.should eq("/api/items")
      ep.method.should eq("POST")
      ep.params.map(&.name).should eq(["q"])
    end

    it "returns nil for a hallucinated url" do
      analyzer.__test_create_endpoint(%({"url":"GET /api/x","method":"GET","params":[]})).should be_nil
      analyzer.__test_create_endpoint(%({"url":"endpoint","method":"GET","params":[]})).should be_nil
    end
  end
end
