require "../../../../spec_helper"
require "../../../../../src/analyzer/analyzers/llm_analyzers/unified_ai"

module LLM
  def self.get_max_tokens(provider_url : String, model_name : String)
    @@mock_max_tokens_value || 1024
  end

  def self.mock_max_tokens=(value : Int32)
    @@mock_max_tokens_value = value
  end

  def self.reset_mock_max_tokens
    @@mock_max_tokens_value = nil
  end
end

# v0 used the now-removed --ollama / --ollama-model flag pair. v1.0
# routes everything through the unified --ai-provider surface, so these
# specs assert max_tokens behavior with `--ai-provider ollama` configs.
describe Analyzer::AI::Unified do
  before_each do
    LLM.reset_mock_max_tokens
  end

  describe "#initialize with --ai-provider ollama" do
    it "uses ai_max_token from options if provided" do
      options = Hash{
        "url"          => YAML::Any.new(""),
        "debug"        => YAML::Any.new(false),
        "verbose"      => YAML::Any.new(false),
        "color"        => YAML::Any.new(false),
        "nolog"        => YAML::Any.new(false),
        "ai_provider"  => YAML::Any.new("ollama"),
        "ai_model"     => YAML::Any.new("test-ollama-model"),
        "ai_max_token" => YAML::Any.new(4096),
        "base"         => YAML::Any.new([YAML::Any.new(".")]),
      }
      analyzer = Analyzer::AI::Unified.new(options)
      analyzer.max_tokens.should eq(4096)
    end

    it "uses LLM.get_max_tokens if ai_max_token is not provided" do
      options = Hash{
        "url"         => YAML::Any.new(""),
        "debug"       => YAML::Any.new(false),
        "verbose"     => YAML::Any.new(false),
        "color"       => YAML::Any.new(false),
        "nolog"       => YAML::Any.new(false),
        "ai_provider" => YAML::Any.new("ollama"),
        "ai_model"    => YAML::Any.new("test-ollama-model"),
        "base"        => YAML::Any.new([YAML::Any.new(".")]),
      }
      analyzer = Analyzer::AI::Unified.new(options)
      analyzer.max_tokens.should eq(1024)
    end
  end
end
