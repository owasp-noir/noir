require "../../../../spec_helper"
require "../../../../../src/analyzer/analyzers/llm_analyzers/unified_ai"

module LLM
  # Mocking get_max_tokens for testing purposes
  def self.get_max_tokens(provider_url : String, model_name : String)
    # Allow dynamic mock behavior if needed, otherwise return a default
    @@mock_max_tokens_value || 1024 # Default mock value
  end

  # Helper to set the mock return value for get_max_tokens
  def self.mock_max_tokens=(value : Int32)
    @@mock_max_tokens_value = value
  end

  def self.reset_mock_max_tokens
    @@mock_max_tokens_value = nil
  end
end

describe Analyzer::AI::Unified do
  before_each do
    LLM.reset_mock_max_tokens
  end

  describe "#initialize" do
    it "uses ai_max_token from options if provided with ai_provider" do
      options = Hash{
        "url"          => YAML::Any.new(""),
        "debug"        => YAML::Any.new(false),
        "verbose"      => YAML::Any.new(false),
        "color"        => YAML::Any.new(false),
        "nolog"        => YAML::Any.new(false),
        "ollama"       => YAML::Any.new(""),
        "ollama_model" => YAML::Any.new(""),
        "ai_provider"  => YAML::Any.new("http://localhost:8000"),
        "ai_model"     => YAML::Any.new("test-model"),
        "ai_key"       => YAML::Any.new("test-key"),
        "ai_max_token" => YAML::Any.new(2048),
        "base"         => YAML::Any.new([YAML::Any.new(".")]),
      }
      analyzer = Analyzer::AI::Unified.new(options)
      analyzer.max_tokens.should eq(2048)
    end

    it "uses LLM.get_max_tokens if ai_max_token is not provided" do
      options = Hash{
        "url"          => YAML::Any.new(""),
        "debug"        => YAML::Any.new(false),
        "verbose"      => YAML::Any.new(false),
        "color"        => YAML::Any.new(false),
        "nolog"        => YAML::Any.new(false),
        "ollama"       => YAML::Any.new(""),
        "ollama_model" => YAML::Any.new(""),
        "ai_provider"  => YAML::Any.new("http://localhost:8000"),
        "ai_model"     => YAML::Any.new("test-model"),
        "ai_key"       => YAML::Any.new("test-key"),
        "base"         => YAML::Any.new([YAML::Any.new(".")]),
      }
      analyzer = Analyzer::AI::Unified.new(options)
      analyzer.max_tokens.should eq(1024)
    end
  end
end
