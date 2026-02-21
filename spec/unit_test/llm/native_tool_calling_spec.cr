require "spec"
require "../../../src/llm/native_tool_calling"

describe LLM::NativeToolCalling do
  describe ".default_allowlist" do
    it "returns the default providers" do
      LLM::NativeToolCalling.default_allowlist.should eq(["openai", "xai", "github"])
    end

    it "returns a cloned list" do
      list = LLM::NativeToolCalling.default_allowlist
      list << "custom"
      LLM::NativeToolCalling.default_allowlist.should eq(["openai", "xai", "github"])
    end
  end

  describe ".default_allowlist_csv" do
    it "returns comma-separated default values" do
      LLM::NativeToolCalling.default_allowlist_csv.should eq("openai,xai,github")
    end
  end

  describe ".canonical_provider" do
    it "canonicalizes known providers from urls and aliases" do
      LLM::NativeToolCalling.canonical_provider("openai").should eq("openai")
      LLM::NativeToolCalling.canonical_provider("https://api.openai.com/v1/chat/completions").should eq("openai")
      LLM::NativeToolCalling.canonical_provider("https://api.x.ai/v1/chat/completions").should eq("xai")
      LLM::NativeToolCalling.canonical_provider("https://models.github.ai/inference/chat/completions").should eq("github")
      LLM::NativeToolCalling.canonical_provider("https://ollama.example/v1/chat/completions").should eq("ollama")
      LLM::NativeToolCalling.canonical_provider("  vllm ").should eq("vllm")
    end

    it "keeps unknown providers as normalized lowercase strings" do
      LLM::NativeToolCalling.canonical_provider(" CustomProvider ").should eq("customprovider")
    end
  end

  describe ".normalize_allowlist" do
    it "uses default allowlist when input is nil" do
      LLM::NativeToolCalling.normalize_allowlist(nil).should eq(["openai", "xai", "github"])
    end

    it "canonicalizes, de-duplicates, and trims custom input" do
      normalized = LLM::NativeToolCalling.normalize_allowlist([
        "https://api.openai.com/v1",
        "openai",
        " https://api.x.ai/v1 ",
        "github",
        "https://models.github.ai/inference/chat/completions",
      ])
      normalized.should eq(["openai", "xai", "github"])
    end
  end
end
