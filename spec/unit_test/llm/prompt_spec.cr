require "spec"
require "../../../src/llm/prompt"

describe LLM do
  it "has a FILTER_PROMPT constant" do
    LLM::FILTER_PROMPT.should_not be_nil
    LLM::FILTER_PROMPT.should contain("Input Files:")
  end

  it "has a FILTER_FORMAT constant" do
    LLM::FILTER_FORMAT.should_not be_nil
  end
  it "has an ANALYZE_PROMPT constant" do
    LLM::ANALYZE_PROMPT.should_not be_nil
    LLM::ANALYZE_PROMPT.should contain("Input Code:")
  end
  it "has an ANALYZE_FORMAT constant" do
    LLM::ANALYZE_FORMAT.should_not be_nil
    LLM::ANALYZE_FORMAT.should contain("\"name\": \"analyze_endpoints\"")
  end
end
