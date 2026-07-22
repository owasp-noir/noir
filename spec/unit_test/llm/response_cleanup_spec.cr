require "../../spec_helper"
require "../../../src/llm/response_cleanup"

describe LLM do
  describe ".strip_json_fences" do
    it "strips markdown json fences and trims whitespace" do
      input = "```json\n{\"key\": \"value\"}\n```"
      LLM.strip_json_fences(input).should eq("{\"key\": \"value\"}")
    end

    it "handles text without fences" do
      input = "  {\"key\": \"value\"}  "
      LLM.strip_json_fences(input).should eq("{\"key\": \"value\"}")
    end
  end
end
