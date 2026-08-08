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

    it "refuses an arbitrary command target (no code execution)" do
      ENV.delete("NOIR_ACP_ALLOW_CUSTOM_COMMAND")
      expect_raises(LLM::ACPClient::UnsupportedACPTargetError, /Unsupported ACP provider target/) do
        LLM::ACPClient.resolve_command("acp:rm -rf /")
      end
    end

    it "allows a custom command only with the explicit opt-in" do
      ENV["NOIR_ACP_ALLOW_CUSTOM_COMMAND"] = "1"
      begin
        command, args = LLM::ACPClient.resolve_command("acp:my-agent --flag")
        command.should eq("my-agent")
        args.should eq(["--flag"])
      ensure
        ENV.delete("NOIR_ACP_ALLOW_CUSTOM_COMMAND")
      end
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

  # The agent asks before running a tool — a shell command, a file write. The
  # prompt driving it is source code from the tree being scanned, so a blanket
  # "yes" turns a scan of an untrusted repo into local code execution.
  describe "#answer_permission_request" do
    permission_request = JSON.parse(<<-JSON)
      {
        "sessionId": "s1",
        "toolCall": {"toolCallId": "t1", "title": "Run shell command", "kind": "execute"},
        "options": [
          {"optionId": "proceed_once", "name": "Yes", "kind": "allow_once"},
          {"optionId": "proceed_always", "name": "Yes, always", "kind": "allow_always"},
          {"optionId": "cancel", "name": "No", "kind": "reject_once"}
        ]
      }
      JSON

    it "rejects a tool permission request by default" do
      ENV.delete("NOIR_ACP_ALLOW_TOOL_PERMISSIONS")
      client = LLM::ACPClient.new("acp:gemini", "gemini")
      outcome = client.answer_permission_request(permission_request)["outcome"]
      outcome["outcome"].should eq("selected")
      outcome["optionId"].should eq("cancel")
    end

    it "allows only with the explicit opt-in, using an id the agent offered" do
      ENV["NOIR_ACP_ALLOW_TOOL_PERMISSIONS"] = "1"
      begin
        client = LLM::ACPClient.new("acp:gemini", "gemini")
        outcome = client.answer_permission_request(permission_request)["outcome"]
        outcome["outcome"].should eq("selected")
        # Not the hardcoded "allow-once" the old code invented — option ids
        # are agent-defined, and only `kind` is standardised.
        outcome["optionId"].should eq("proceed_once")
      ensure
        ENV.delete("NOIR_ACP_ALLOW_TOOL_PERMISSIONS")
      end
    end

    it "cancels when the agent offers no way to decline" do
      ENV.delete("NOIR_ACP_ALLOW_TOOL_PERMISSIONS")
      allow_only = JSON.parse(<<-JSON)
        {
          "sessionId": "s1",
          "toolCall": {"toolCallId": "t1", "title": "Write file", "kind": "edit"},
          "options": [{"optionId": "yes", "name": "Yes", "kind": "allow_once"}]
        }
        JSON

      client = LLM::ACPClient.new("acp:gemini", "gemini")
      outcome = client.answer_permission_request(allow_only)["outcome"]
      outcome["outcome"].should eq("cancelled")
      outcome["optionId"]?.should be_nil
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
