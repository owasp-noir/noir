require "../../../../spec_helper"
require "../../../../../src/analyzer/analyzers/llm_analyzers/ollama"
# The LLM module mock should be available from general_spec.cr if run together,
# or ensure it's defined/required if running specs independently.
# For robustness, we can redefine it or ensure it's in a shared helper.
# For now, assuming it might be available or let's redefine for clarity if needed.

# If LLM mock isn't automatically shared, redefine or require from a shared spec helper.
# To be safe, let's ensure the mock is available.
# This module might already be defined if general_spec.cr ran first.
module LLM
  def self.get_max_tokens(provider_url : String, model_name : String)
    @@mock_max_tokens_value || 1024
  end

  def self.set_mock_max_tokens(value : Int32)
    @@mock_max_tokens_value = value
  end

  def self.reset_mock_max_tokens
    @@mock_max_tokens_value = nil
  end
end

describe Analyzer::AI::Ollama do
  before_each do
    LLM.reset_mock_max_tokens
  end

  describe "#initialize" do
    it "uses ai_max_token from options if provided" do
      options = Hash{
        "url" => YAML::Any.new(""),
        "debug" => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color" => YAML::Any.new(false),
        "nolog" => YAML::Any.new(false),
        "ollama" => YAML::Any.new(""),
        "ollama_model" => YAML::Any.new(""),
        "ai_provider"       => YAML::Any.new("http://localhost:11434"),
        "ai_model" => YAML::Any.new("test-ollama-model"),
        "ai_max_token" => YAML::Any.new(4096), # Different value for testing
        "base"         => YAML::Any.new("."),
      }
      analyzer = Analyzer::AI::Ollama.new(options)
      analyzer.max_tokens.should eq(4096)
    end

    it "uses LLM.get_max_tokens if ai_max_token is not provided" do
      LLM.set_mock_max_tokens(768)
      options = Hash{
        "url" => YAML::Any.new(""),
        "debug" => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color" => YAML::Any.new(false),
        "nolog" => YAML::Any.new(false),
        "ollama" => YAML::Any.new(""),
        "ollama_model" => YAML::Any.new(""),
        "ai_provider"       => YAML::Any.new("http://localhost:11434"),
        "ai_model" => YAML::Any.new("test-ollama-model"),
        "base"         => YAML::Any.new("."),
      }
      analyzer = Analyzer::AI::Ollama.new(options)
      analyzer.max_tokens.should eq(768)
    end

    it "uses LLM.get_max_tokens if ai_max_token is nil" do
      LLM.set_mock_max_tokens(384)
      options = Hash{
        "url" => YAML::Any.new(""),
        "debug" => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color" => YAML::Any.new(false),
        "nolog" => YAML::Any.new(false),
        "ollama" => YAML::Any.new(""),
        "ollama_model" => YAML::Any.new(""),
        "ai_provider"       => YAML::Any.new("http://localhost:11434"),
        "ai_model" => YAML::Any.new("test-ollama-model"),
        "ai_max_token" => YAML::Any.new(nil), # Explicitly nil
        "base"         => YAML::Any.new("."),
      }
      analyzer = Analyzer::AI::Ollama.new(options)
      analyzer.max_tokens.should eq(384)
    end
  end
end
