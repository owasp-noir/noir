require "spec"
require "../../../src/llm/prompt"

describe LLM do
  it "has a FILTER_PROMPT constant" do
    LLM::FILTER_PROMPT.should_not be_nil
    LLM::FILTER_PROMPT.should contain("Input Files:")
  end

  it "has a FILTER_FORMAT constant" do
    LLM::FILTER_FORMAT.should_not be_nil
    LLM::FILTER_FORMAT.should contain("\"type\": \"json_schema\"")
  end

  it "has an ANALYZE_PROMPT constant" do
    LLM::ANALYZE_PROMPT.should_not be_nil
    LLM::ANALYZE_PROMPT.should contain("Input Code:")
  end
  it "has an ANALYZE_FORMAT constant" do
    LLM::ANALYZE_FORMAT.should_not be_nil
    LLM::ANALYZE_FORMAT.should contain("\"name\": \"analyze_endpoints\"")
  end

  describe "MODEL_TOKEN_LIMITS" do
    it "includes gpt-5.1 with correct token limit" do
      openai_limits = LLM::MODEL_TOKEN_LIMITS["openai"].as(Hash)
      openai_limits["gpt-5.1"].should eq(400000)
    end

    it "includes grok-4-fast-reasoning with correct token limit" do
      xai_limits = LLM::MODEL_TOKEN_LIMITS["xai"].as(Hash)
      xai_limits["grok-4-fast-reasoning"].should eq(256000)
    end

    it "includes grok-4-fast-non-reasoning with correct token limit" do
      xai_limits = LLM::MODEL_TOKEN_LIMITS["xai"].as(Hash)
      xai_limits["grok-4-fast-non-reasoning"].should eq(256000)
    end

    it "includes claude-sonnet-4-5 with correct token limit" do
      anthropic_limits = LLM::MODEL_TOKEN_LIMITS["anthropic"].as(Hash)
      anthropic_limits["claude-sonnet-4-5"].should eq(200000)
    end

    it "includes claude-haiku-4-5 with correct token limit" do
      anthropic_limits = LLM::MODEL_TOKEN_LIMITS["anthropic"].as(Hash)
      anthropic_limits["claude-haiku-4-5"].should eq(200000)
    end

    it "includes claude-opus-4-1 with correct token limit" do
      anthropic_limits = LLM::MODEL_TOKEN_LIMITS["anthropic"].as(Hash)
      anthropic_limits["claude-opus-4-1"].should eq(200000)
    end
  end
end
