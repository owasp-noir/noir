require "spec"
require "../../../src/llm/prompt_overrides"

describe LLM::PromptOverrides do
  before_each do
    LLM::PromptOverrides.reset
  end

  describe "prompt overrides" do
    it "returns default filter prompt when no override is set" do
      default_prompt = LLM::PromptOverrides.filter_prompt
      default_prompt.should contain("Analyze the following list of file paths")
    end

    it "returns overridden filter prompt when set" do
      test_prompt = "Custom filter prompt for testing"
      LLM::PromptOverrides.filter_prompt = test_prompt
      LLM::PromptOverrides.filter_prompt.should eq(test_prompt)
    end

    it "returns empty string when override is empty string" do
      LLM::PromptOverrides.filter_prompt = ""
      LLM::PromptOverrides.filter_prompt.should eq("")
    end

    it "returns default analyze prompt when no override is set" do
      default_prompt = LLM::PromptOverrides.analyze_prompt
      default_prompt.should contain("Analyze the provided source code")
    end

    it "returns overridden analyze prompt when set" do
      test_prompt = "Custom analyze prompt for testing"
      LLM::PromptOverrides.analyze_prompt = test_prompt
      LLM::PromptOverrides.analyze_prompt.should eq(test_prompt)
    end

    it "returns default bundle analyze prompt when no override is set" do
      default_prompt = LLM::PromptOverrides.bundle_analyze_prompt
      default_prompt.should contain("Analyze the following bundle of source code files")
    end

    it "returns overridden bundle analyze prompt when set" do
      test_prompt = "Custom bundle analyze prompt for testing"
      LLM::PromptOverrides.bundle_analyze_prompt = test_prompt
      LLM::PromptOverrides.bundle_analyze_prompt.should eq(test_prompt)
    end

    it "returns default llm optimize prompt when no override is set" do
      default_prompt = LLM::PromptOverrides.llm_optimize_prompt
      default_prompt.should contain("Analyze the provided endpoint and optimize it")
    end

    it "returns overridden llm optimize prompt when set" do
      test_prompt = "Custom LLM optimize prompt for testing"
      LLM::PromptOverrides.llm_optimize_prompt = test_prompt
      LLM::PromptOverrides.llm_optimize_prompt.should eq(test_prompt)
    end
  end

  describe "reset" do
    it "resets all overrides to nil" do
      LLM::PromptOverrides.filter_prompt = "filter"
      LLM::PromptOverrides.analyze_prompt = "analyze"
      LLM::PromptOverrides.bundle_analyze_prompt = "bundle"
      LLM::PromptOverrides.llm_optimize_prompt = "optimize"

      LLM::PromptOverrides.reset

      LLM::PromptOverrides.filter_prompt.should contain("Analyze the following list of file paths")
      LLM::PromptOverrides.analyze_prompt.should contain("Analyze the provided source code")
      LLM::PromptOverrides.bundle_analyze_prompt.should contain("Analyze the following bundle of source code files")
      LLM::PromptOverrides.llm_optimize_prompt.should contain("Analyze the provided endpoint and optimize it")
    end
  end
end
