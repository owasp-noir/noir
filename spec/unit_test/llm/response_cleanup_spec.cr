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

    it "strips a fence whatever language tag the model chose" do
      # The old rule only knew the exact lowercase `json` tag, so any other
      # spelling left the bare language word in front of the payload,
      # `JSON.parse` failed, and the caller returned "" — which the analyzer
      # reads as "this code defines no endpoints".
      ["JSON", "Json", "javascript", "js", ""].each do |tag|
        LLM.strip_json_fences("```#{tag}\n{\"key\": \"value\"}\n```")
          .should eq("{\"key\": \"value\"}")
      end
    end

    it "keeps backticks that belong to the data" do
      # The model quotes code it was asked to read; a `snippet` or
      # `description` value carrying backticks used to have them deleted
      # from the payload by a whole-string gsub.
      input = %({"snippet": "run `ls` first", "fence": "```json"})
      LLM.strip_json_fences(input).should eq(input)
    end

    it "keeps interior backticks when the payload is also fenced" do
      input = "```json\n" + %({"snippet": "use ``` to fence"}) + "\n```"
      LLM.strip_json_fences(input).should eq(%({"snippet": "use ``` to fence"}))
    end

    it "leaves a fence-free payload that merely ends with backticks alone" do
      input = %({"snippet": "trailing ```"})
      LLM.strip_json_fences(input).should eq(input)
    end
  end
end
