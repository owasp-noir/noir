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

    it "pulls a fenced JSON block out of surrounding prose" do
      input = "Here are the endpoints:\n```json\n{\"endpoints\": []}\n```\nHope this helps."
      LLM.strip_json_fences(input).should eq(%({"endpoints": []}))
    end

    it "pulls an unfenced JSON object out of surrounding prose" do
      input = "Sure! {\"endpoints\": [{\"url\": \"/a\"}]} Let me know."
      LLM.strip_json_fences(input).should eq(%({"endpoints": [{"url": "/a"}]}))
    end

    it "ignores braces in prose after a fenced reply" do
      input = "```json\n{\"endpoints\": []}\n```\nNote /users/{id} too."
      LLM.strip_json_fences(input).should eq(%({"endpoints": []}))
    end

    it "ignores braces in prose after an unfenced reply" do
      input = %({"endpoints": [{"url": "/users/{id}"}]} Note /users/{id} too.)
      LLM.strip_json_fences(input).should eq(%({"endpoints": [{"url": "/users/{id}"}]}))
    end

    it "prefers a json block over a code block before it" do
      input = "The route:\n```python\n@app.get('/a')\ndef a(): return {}\n```\nResult:\n```json\n{\"endpoints\": []}\n```"
      LLM.strip_json_fences(input).should eq(%({"endpoints": []}))
    end

    it "skips a brace in prose before the object" do
      input = %(Route /users/{id} found: {"endpoints": [{"url": "/users/{id}", "note": "a } in a string"}]})
      LLM.strip_json_fences(input).should eq(%({"endpoints": [{"url": "/users/{id}", "note": "a } in a string"}]}))
    end

    it "slices on character boundaries around non-ASCII prose" do
      input = %(엔드포인트입니다: {"endpoints": [{"url": "/사용자"}]} 감사합니다)
      LLM.strip_json_fences(input).should eq(%({"endpoints": [{"url": "/사용자"}]}))
    end

    it "returns a truncated reply unparsed rather than a fragment of it" do
      input = %({"endpoints":[{"url":"/users","method":"GET"},{"url":"/ord)
      LLM.strip_json_fences(input).should eq(input)
    end

    it "leaves a reply with no JSON object in it alone" do
      LLM.strip_json_fences("null").should eq("null")
      LLM.strip_json_fences("no endpoints found").should eq("no endpoints found")
    end
  end
end
