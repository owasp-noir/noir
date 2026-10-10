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

  describe ".json_reply" do
    endpoints = ->(text : String) { LLM.json_reply(text, "endpoints").try(&.to_json) }

    it "pulls a fenced JSON block out of surrounding prose" do
      endpoints.call("Here are the endpoints:\n```json\n{\"endpoints\": []}\n```\nHope this helps.").should eq(%({"endpoints":[]}))
    end

    it "pulls an unfenced JSON object out of surrounding prose" do
      endpoints.call(%(Sure! {"endpoints": [{"url": "/a"}]} Let me know.)).should eq(%({"endpoints":[{"url":"/a"}]}))
    end

    it "ignores braces in prose after a fenced reply" do
      endpoints.call("```json\n{\"endpoints\": []}\n```\nNote /users/{id} too.").should eq(%({"endpoints":[]}))
    end

    it "ignores braces in prose after an unfenced reply" do
      endpoints.call(%({"endpoints": [{"url": "/users/{id}"}]} Note /users/{id} too.))
        .should eq(%({"endpoints":[{"url":"/users/{id}"}]}))
    end

    it "prefers a json block over a code block before it" do
      input = "The route:\n```python\n@app.get('/a')\ndef a(): return {}\n```\nResult:\n```json\n{\"endpoints\": []}\n```"
      endpoints.call(input).should eq(%({"endpoints":[]}))
    end

    it "skips a brace in prose before the object" do
      endpoints.call(%(Route /users/{id} found: {"endpoints": [{"url": "/users/{id}", "note": "a } in a string"}]}))
        .should eq(%({"endpoints":[{"url":"/users/{id}","note":"a } in a string"}]}))
    end

    it "slices on character boundaries around non-ASCII prose" do
      endpoints.call(%(엔드포인트입니다: {"endpoints": [{"url": "/사용자"}]} 감사합니다)).should eq(%({"endpoints":[{"url":"/사용자"}]}))
    end

    it "skips a complete object without the key before the answer" do
      endpoints.call(%({"thought":"scanning"} {"endpoints":[{"url":"/a"}]})).should eq(%({"endpoints":[{"url":"/a"}]}))
    end

    # Each of these used to read as "no endpoints", get cached, and pass
    # --strict.
    {
      "a provider error object"             => %({"error":"context length exceeded"}),
      "an object under another key"         => %({"result":[]}),
      "routes under another name"           => %({"routes":[{"url":"/a"}]}),
      "a bare array of endpoint objects"    => %(Answer: [{"url":"/a"}]),
      "a preamble before a truncated reply" => %({"thought":"scanning"} {"endpoints":[{"url":"/a"},{"url":"/b),
      "a truncated reply"                   => %({"endpoints":[{"url":"/users","method":"GET"},{"url":"/ord),
      "null"                                => "null",
      "prose"                               => "no endpoints found",
    }.each do |label, reply|
      it "finds no answer in #{label}" do
        LLM.json_reply(reply, "endpoints").should be_nil
      end
    end

    it "returns an empty object as the model's empty answer" do
      LLM.json_reply("{}", "endpoints").should eq({} of String => JSON::Any)
      LLM.json_reply("```json\n{}\n```", "endpoints").should eq({} of String => JSON::Any)
    end
  end

  describe ".salvage_list" do
    it "keeps the complete items before the cut" do
      reply = %(```json\n{"endpoints": [ {"url":"/a","params":[{"name":"q"}]}, {"url":"/b}"} ,{"url":"/ord)
      LLM.salvage_list(reply, "endpoints").try(&.map(&.["url"].as_s)).should eq(["/a", "/b}"])
    end

    it "stops at the end of the list" do
      LLM.salvage_list(%({"endpoints":[{"url":"/a"}],"note":{"url":"/x"}, "more":), "endpoints").try(&.size).should eq(1)
    end

    it "finds nothing without a complete item" do
      LLM.salvage_list(%({"endpoints":[{"url":"/a), "endpoints").should be_nil
      LLM.salvage_list(%({"files":[{"url":"/a"}), "endpoints").should be_nil
      LLM.salvage_list("prose", "endpoints").should be_nil
    end
  end
end
