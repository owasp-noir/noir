require "../../spec_helper"
require "../../../src/llm/adapter"

# Minimal Adapter implementation that records every delegated call so
# specs can verify the default fallback methods in the `Adapter`
# module without touching the real HTTP clients.
private class RecordingAdapter
  include LLM::Adapter

  property calls : Array(NamedTuple(method: String, payload: String))

  def initialize
    @calls = [] of NamedTuple(method: String, payload: String)
  end

  def request_messages(messages : Messages, format : String = "json") : String
    @calls << {method: "request_messages:#{format}", payload: messages.to_json}
    "OK"
  end

  def request(prompt : String, format : String = "json") : String
    @calls << {method: "request:#{format}", payload: prompt}
    "OK"
  end
end

describe LLM::Adapter do
  describe "default supports_* methods" do
    it "reports no native tool calling by default" do
      RecordingAdapter.new.supports_native_tool_calling?.should be_false
    end

    it "reports no server-side context by default" do
      RecordingAdapter.new.supports_context?.should be_false
    end
  end

  describe "default close" do
    it "is a no-op that returns nil" do
      RecordingAdapter.new.close.should be_nil
    end
  end

  describe "default request_messages_with_tools" do
    it "falls back to request_messages with json format and ignores tools payload" do
      adapter = RecordingAdapter.new
      adapter.request_messages_with_tools([{"role" => "user", "content" => "hi"}], "tools-json").should eq("OK")
      # The default impl drops `tools` and forces format=json.
      adapter.calls.size.should eq(1)
      adapter.calls.first[:method].should eq("request_messages:json")
    end
  end

  describe "default request_with_context" do
    it "skips the system slot when system is nil" do
      adapter = RecordingAdapter.new
      adapter.request_with_context(nil, "u", "json", "ck").should eq("OK")
      payload = adapter.calls.first[:payload]
      payload.should_not contain("\"role\":\"system\"")
      payload.should contain("\"role\":\"user\"")
    end

    it "skips the system slot when system is an empty string" do
      adapter = RecordingAdapter.new
      adapter.request_with_context("", "u").should eq("OK")
      adapter.calls.first[:payload].should_not contain("\"role\":\"system\"")
    end

    it "emits both system and user when system is present" do
      adapter = RecordingAdapter.new
      adapter.request_with_context("you are an api scanner", "find endpoints in /app").should eq("OK")
      payload = adapter.calls.first[:payload]
      payload.should contain("\"role\":\"system\"")
      payload.should contain("you are an api scanner")
      payload.should contain("\"role\":\"user\"")
      payload.should contain("find endpoints in /app")
    end
  end
end

describe LLM::OllamaAdapter do
  describe ".flatten_messages" do
    it "returns {nil, \"\"} for an empty message list" do
      sys, usr = LLM::OllamaAdapter.flatten_messages([] of Hash(String, String))
      sys.should be_nil
      usr.should eq("")
    end

    it "joins multiple system messages with \\n\\n" do
      sys, usr = LLM::OllamaAdapter.flatten_messages([
        {"role" => "system", "content" => "rule A"},
        {"role" => "system", "content" => "rule B"},
        {"role" => "user", "content" => "ask"},
      ])
      sys.should eq("rule A\n\nrule B")
      usr.should eq("ask")
    end

    it "joins multiple user messages with \\n\\n" do
      sys, usr = LLM::OllamaAdapter.flatten_messages([
        {"role" => "user", "content" => "first"},
        {"role" => "user", "content" => "second"},
      ])
      sys.should be_nil
      usr.should eq("first\n\nsecond")
    end

    it "returns nil system when no system messages were present" do
      sys, _ = LLM::OllamaAdapter.flatten_messages([
        {"role" => "user", "content" => "lonely user"},
      ])
      sys.should be_nil
    end

    it "drops messages with roles other than system / user" do
      sys, usr = LLM::OllamaAdapter.flatten_messages([
        {"role" => "system", "content" => "S"},
        {"role" => "assistant", "content" => "A"},
        {"role" => "user", "content" => "U"},
        {"role" => "tool", "content" => "T"},
      ])
      sys.should eq("S")
      usr.should eq("U")
    end
  end
end

describe LLM::AdapterFactory do
  describe ".for" do
    it "returns an ACPAdapter for acp:* providers" do
      adapter = LLM::AdapterFactory.for("acp:codex", "")
      adapter.should be_a(LLM::ACPAdapter)
    end

    it "returns an OllamaAdapter when the provider mentions ollama" do
      adapter = LLM::AdapterFactory.for("ollama", "llama3")
      adapter.should be_a(LLM::OllamaAdapter)
    end

    it "returns an OllamaAdapter for an ollama:// URL form" do
      adapter = LLM::AdapterFactory.for("http://example.com/ollama", "llama3")
      adapter.should be_a(LLM::OllamaAdapter)
    end

    it "returns a GeneralAdapter for any non-ACP / non-ollama provider" do
      adapter = LLM::AdapterFactory.for("openai", "gpt-4o", "sk-fake")
      adapter.should be_a(LLM::GeneralAdapter)
    end
  end

  describe ".native_tool_calling_enabled_for_provider?" do
    it "respects the allowlist when one is supplied" do
      LLM::AdapterFactory.native_tool_calling_enabled_for_provider?("openai", ["openai"]).should be_true
      LLM::AdapterFactory.native_tool_calling_enabled_for_provider?("openai", ["anthropic"]).should be_false
    end

    it "honors the canonical-provider normalization (case insensitive)" do
      LLM::AdapterFactory.native_tool_calling_enabled_for_provider?("OpenAI", ["openai"]).should be_true
    end

    it "follows the default allowlist when no allowlist is supplied" do
      # Default allowlist is whatever NativeToolCalling.default_allowlist
      # produces — just sanity-check it consistently agrees with the
      # normalize path on a known provider.
      default_decision = LLM::AdapterFactory.native_tool_calling_enabled_for_provider?("openai")
      normalized_decision = LLM::NativeToolCalling.normalize_allowlist(nil).includes?(
        LLM::NativeToolCalling.canonical_provider("openai")
      )
      default_decision.should eq(normalized_decision)
    end
  end
end

describe LLM::GeneralAdapter do
  describe "#supports_native_tool_calling?" do
    it "mirrors the constructor flag" do
      client = LLM::General.new("https://example.test", "gpt-4o", "sk-fake")
      LLM::GeneralAdapter.new(client, native_tool_calling_enabled: true).supports_native_tool_calling?.should be_true
      LLM::GeneralAdapter.new(client, native_tool_calling_enabled: false).supports_native_tool_calling?.should be_false
    end
  end
end

describe LLM::OllamaAdapter do
  describe "#supports_context?" do
    it "reports true (Ollama exposes KV context reuse)" do
      client = LLM::Ollama.new("http://localhost:11434", "llama3")
      LLM::OllamaAdapter.new(client).supports_context?.should be_true
    end
  end
end
