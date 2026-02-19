require "spec"
require "../../../src/llm/acp/client"
require "../../../src/llm/adapter"

describe LLM::ACPClient do
  describe ".acp_provider?" do
    it "detects acp providers" do
      LLM::ACPClient.acp_provider?("acp:codex").should be_true
      LLM::ACPClient.acp_provider?("acp:gemini").should be_true
      LLM::ACPClient.acp_provider?("acp:claude").should be_true
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

    it "maps claude to npx claude agent acp adapter" do
      command, args = LLM::ACPClient.resolve_command("acp:claude")
      command.should eq("npx")
      args.should eq(["@zed-industries/claude-agent-acp"])
    end

    it "maps claude-code alias to npx claude agent acp adapter" do
      command, args = LLM::ACPClient.resolve_command("acp:claude-code")
      command.should eq("npx")
      args.should eq(["@zed-industries/claude-agent-acp"])
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

  it "enables native tool-calling for openai provider" do
    adapter = LLM::AdapterFactory.for("openai", "gpt-4o-mini", nil)
    adapter.should be_a(LLM::GeneralAdapter)
    adapter.supports_native_tool_calling?.should be_true
  end

  it "enables native tool-calling for github provider url" do
    adapter = LLM::AdapterFactory.for("https://models.github.ai/inference/chat/completions", "gpt-4o", nil)
    adapter.should be_a(LLM::GeneralAdapter)
    adapter.supports_native_tool_calling?.should be_true
  end

  it "disables native tool-calling for non-allowlisted providers" do
    adapter = LLM::AdapterFactory.for("azure", "gpt-4o", nil)
    adapter.should be_a(LLM::GeneralAdapter)
    adapter.supports_native_tool_calling?.should be_false
  end

  it "keeps default allowlist when custom allowlist is nil" do
    LLM::AdapterFactory.native_tool_calling_enabled_for_provider?("openai", nil).should be_true
    LLM::AdapterFactory.native_tool_calling_enabled_for_provider?("azure", nil).should be_false
  end

  it "applies custom allowlist when provided" do
    adapter = LLM::AdapterFactory.for("openai", "gpt-4o-mini", nil, nil, ["github"])
    adapter.should be_a(LLM::GeneralAdapter)
    adapter.supports_native_tool_calling?.should be_false

    adapter2 = LLM::AdapterFactory.for("github", "gpt-4o", nil, nil, ["github"])
    adapter2.should be_a(LLM::GeneralAdapter)
    adapter2.supports_native_tool_calling?.should be_true
  end

  it "canonicalizes URL entries in custom allowlist" do
    LLM::AdapterFactory.native_tool_calling_enabled_for_provider?("openai", ["https://api.openai.com/v1"]).should be_true
    LLM::AdapterFactory.native_tool_calling_enabled_for_provider?("xai", ["https://api.x.ai/v1"]).should be_true
    LLM::AdapterFactory.native_tool_calling_enabled_for_provider?("github", ["https://models.github.ai/inference/chat/completions"]).should be_true
  end
end
