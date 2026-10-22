require "../../../../spec_helper"
require "../../../../../src/analyzer/analyzers/llm_analyzers/unified_ai"

# Bundle requests are metered provider calls, so the fan-out is bounded
# instead of "one fiber per bundle". Exposed for assertion because the
# alternative is watching a real provider rate-limit the scan.
class Analyzer::AI::Unified
  def __test_bundle_worker_count(total : Int32) : Int32
    bundle_worker_count(total)
  end
end

private def ai_options(provider : String, concurrency : String? = nil) : Hash(String, YAML::Any)
  options = Hash{
    "url"         => YAML::Any.new(""),
    "debug"       => YAML::Any.new(false),
    "verbose"     => YAML::Any.new(false),
    "color"       => YAML::Any.new(false),
    "nolog"       => YAML::Any.new(true),
    "ai_provider" => YAML::Any.new(provider),
    "ai_model"    => YAML::Any.new("test-model"),
    "base"        => YAML::Any.new([YAML::Any.new(".")]),
  }
  options["concurrency"] = YAML::Any.new(concurrency) if concurrency
  options
end

describe Analyzer::AI::Unified do
  describe "#bundle_worker_count" do
    it "follows --concurrency" do
      analyzer = Analyzer::AI::Unified.new(ai_options("openai", "3"))
      analyzer.__test_bundle_worker_count(50).should eq(3)
    end

    it "caps the fan-out regardless of a high --concurrency" do
      analyzer = Analyzer::AI::Unified.new(ai_options("openai", "128"))
      analyzer.__test_bundle_worker_count(500).should eq(Analyzer::AI::Unified::MAX_BUNDLE_WORKERS)
    end

    it "never starts more workers than there are bundles" do
      analyzer = Analyzer::AI::Unified.new(ai_options("openai", "8"))
      analyzer.__test_bundle_worker_count(2).should eq(2)
      analyzer.__test_bundle_worker_count(1).should eq(1)
    end

    it "serializes ACP providers, which share one agent session" do
      analyzer = Analyzer::AI::Unified.new(ai_options("acp:gemini", "16"))
      analyzer.__test_bundle_worker_count(50).should eq(1)
    end

    it "stays valid when no concurrency option is present" do
      analyzer = Analyzer::AI::Unified.new(ai_options("openai"))
      analyzer.__test_bundle_worker_count(50).should eq(1)
    end

    it "stays valid for a nonsense concurrency value" do
      analyzer = Analyzer::AI::Unified.new(ai_options("openai", "0"))
      analyzer.__test_bundle_worker_count(50).should eq(1)
      analyzer = Analyzer::AI::Unified.new(ai_options("openai", "nope"))
      analyzer.__test_bundle_worker_count(50).should eq(1)
    end
  end
end
