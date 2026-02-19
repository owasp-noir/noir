require "spec"
require "../../../src/llm/acp/client"
require "../../../src/llm/adapter"

describe LLM::ACPClient do
  describe ".acp_provider?" do
    it "detects acp providers" do
      LLM::ACPClient.acp_provider?("acp:codex").should be_true
      LLM::ACPClient.acp_provider?("acp:gemini").should be_true
      LLM::ACPClient.acp_provider?("openai").should be_false
    end
  end

  describe ".resolve_command" do
    it "maps codex to npx codex acp adapter" do
      command, args = LLM::ACPClient.resolve_command("acp:codex")
      command.should eq("npx")
      args.should eq(["@zed-industries/codex-acp"])
    end

    it "maps gemini to experimental acp mode" do
      command, args = LLM::ACPClient.resolve_command("acp:gemini")
      command.should eq("gemini")
      args.should eq(["--experimental-acp"])
    end
  end

  describe ".default_model" do
    it "uses target name when model is empty" do
      LLM::ACPClient.default_model("acp:codex", "").should eq("codex")
    end

    it "keeps explicit model when provided" do
      LLM::ACPClient.default_model("acp:codex", "custom-model").should eq("custom-model")
    end
  end
end

describe LLM::AdapterFactory do
  it "returns ACP adapter for acp providers" do
    adapter = LLM::AdapterFactory.for("acp:codex", "", nil)
    adapter.should be_a(LLM::ACPAdapter)
    adapter.close
  end
end
