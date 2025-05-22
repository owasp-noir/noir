require "../../../../spec_helper"
require "../../../../../src/analyzer/analyzers/llm_analyzers/general"
require "../../../../../src/llm/general/client" # To mock LLM module

module LLM
  # Mocking get_max_tokens for testing purposes
  def self.get_max_tokens(provider_url : String, model_name : String)
    # Allow dynamic mock behavior if needed, otherwise return a default
    @@mock_max_tokens_value || 1024 # Default mock value
  end

  # Helper to set the mock return value for get_max_tokens
  def self.set_mock_max_tokens(value : Int32)
    @@mock_max_tokens_value = value
  end

  def self.reset_mock_max_tokens
    @@mock_max_tokens_value = nil
  end
end

describe Analyzer::AI::General do
  before_each do
    LLM.reset_mock_max_tokens
  end

  describe "#initialize" do
    it "uses ai_max_token from options if provided" do
      options = Hash{
        "ai_provider"  => YAML::Any.new("http://localhost:8000"),
        "ai_model"     => YAML::Any.new("test-model"),
        "ai_key"       => YAML::Any.new("test-key"),
        "ai_max_token" => YAML::Any.new(2048),
        "base"         => YAML::Any.new("."),
      }
      analyzer = Analyzer::AI::General.new(options)
      analyzer.max_tokens.should eq(2048)
    end

    it "uses LLM.get_max_tokens if ai_max_token is not provided" do
      LLM.set_mock_max_tokens(512) # Set a specific mock value for this test
      options = Hash{
        "ai_provider" => YAML::Any.new("http://localhost:8000"),
        "ai_model"    => YAML::Any.new("test-model"),
        "ai_key"      => YAML::Any.new("test-key"),
        "base"        => YAML::Any.new("."),
      }
      analyzer = Analyzer::AI::General.new(options)
      analyzer.max_tokens.should eq(512)
    end

    it "uses LLM.get_max_tokens if ai_max_token is nil" do
      LLM.set_mock_max_tokens(256) # Set a specific mock value for this test
      options = Hash{
        "ai_provider"  => YAML::Any.new("http://localhost:8000"),
        "ai_model"     => YAML::Any.new("test-model"),
        "ai_key"       => YAML::Any.new("test-key"),
        "ai_max_token" => YAML::Any.new(nil), # Explicitly nil
        "base"         => YAML::Any.new("."),
      }
      analyzer = Analyzer::AI::General.new(options)
      analyzer.max_tokens.should eq(256)
    end
  end
end
