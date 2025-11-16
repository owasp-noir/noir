require "spec"
require "../../../src/llm/prompt"

describe LLM do
  it "has a FILTER_PROMPT constant" do
    LLM::FILTER_PROMPT.should_not be_nil
    LLM::FILTER_PROMPT.should contain("Input Files:")
  end

  it "has a FILTER_FORMAT constant" do
    LLM::FILTER_FORMAT.should_not be_nil
    LLM::FILTER_FORMAT.should contain("\"type\": \"json_schema\"")
  end

  it "has an ANALYZE_PROMPT constant" do
    LLM::ANALYZE_PROMPT.should_not be_nil
    LLM::ANALYZE_PROMPT.should contain("Input Code:")
  end

  it "has an ANALYZE_FORMAT constant" do
    LLM::ANALYZE_FORMAT.should_not be_nil
    LLM::ANALYZE_FORMAT.should contain("\"name\": \"analyze_endpoints\"")
  end

  describe "MODEL_TOKEN_LIMITS" do
    # Crystal에서는 `let` 대신 `def`로 게으른 변수 정의
    limits = LLM::MODEL_TOKEN_LIMITS

    context "openai" do
      openai = limits["openai"].as(Hash(String, Int32))

      it "includes gpt-3.5-turbo with 16385 tokens" do
        openai["gpt-3.5-turbo"].should eq(16385)
      end

      it "includes gpt-4o with 128000 tokens" do
        openai["gpt-4o"].should eq(128000)
      end

      it "includes o3-mini with 200000 tokens" do
        openai["o3-mini"].should eq(200000)
      end

      it "includes gpt-5.1 with 1000000 tokens" do
        openai["gpt-5.1"].should eq(1000000)
      end

      it "has default of 8000" do
        openai["default"].should eq(8000)
      end
    end

    context "xai" do
      xai = limits["xai"].as(Hash(String, Int32))

      it "includes grok-3 with 1000000 tokens" do
        xai["grok-3"].should eq(1000000)
      end

      it "includes grok-4 with 2000000 tokens" do
        xai["grok-4"].should eq(2000000)
      end

      it "includes grok-4-fast-reasoning with 2000000 tokens" do
        xai["grok-4-fast-reasoning"].should eq(2000000)
      end

      it "includes grok-4-fast-non-reasoning with 2000000 tokens" do
        xai["grok-4-fast-non-reasoning"].should eq(2000000)
      end

      it "includes grok-code-fast-1 with 2000000 tokens" do
        xai["grok-code-fast-1"].should eq(2000000)
      end

      it "has default of 8000" do
        xai["default"].should eq(8000)
      end
    end

    context "anthropic" do
      anthropic = limits["anthropic"].as(Hash(String, Int32))

      it "includes claude-3-5-sonnet with 200000 tokens" do
        anthropic["claude-3-5-sonnet"].should eq(200000)
      end

      it "includes claude-sonnet-4 with 1000000 tokens" do
        anthropic["claude-sonnet-4"].should eq(1000000)
      end

      it "includes claude-sonnet-4-5 with 1000000 tokens" do
        anthropic["claude-sonnet-4-5"].should eq(1000000)
      end

      it "includes claude-haiku-4-5 with 200000 tokens" do
        anthropic["claude-haiku-4-5"].should eq(200000)
      end

      it "includes claude-opus-4-1 with 200000 tokens" do
        anthropic["claude-opus-4-1"].should eq(200000)
      end

      it "has default of 100000" do
        anthropic["default"].should eq(100000)
      end
    end

    context "azure" do
      azure = limits["azure"].as(Hash(String, Int32))

      it "includes gpt-4o-mini with 128000 tokens" do
        azure["gpt-4o-mini"].should eq(128000)
      end

      it "includes gpt-4.1 with 1000000 tokens" do
        azure["gpt-4.1"].should eq(1000000)
      end

      it "has default of 8000" do
        azure["default"].should eq(8000)
      end
    end

    context "github" do
      github = limits["github"].as(Hash(String, Int32))

      it "includes gpt-4o with 64000 tokens (Copilot limit)" do
        github["gpt-4o"].should eq(64000)
      end

      it "includes Meta-Llama-3.1-405B-Instruct with 128000 tokens" do
        github["Meta-Llama-3.1-405B-Instruct"].should eq(128000)
      end

      it "includes Mistral-small with 32768 tokens" do
        github["Mistral-small"].should eq(32768)
      end

      it "has default of 8000" do
        github["default"].should eq(8000)
      end
    end

    context "ollama" do
      ollama = limits["ollama"].as(Hash(String, Int32))

      it "includes llama3.1 with 128000 tokens" do
        ollama["llama3.1"].should eq(128000)
      end

      it "includes llama3.2 with 128000 tokens" do
        ollama["llama3.2"].should eq(128000)
      end

      it "includes phi3 with 128000 tokens" do
        ollama["phi3"].should eq(128000)
      end

      it "includes mistral with 32768 tokens" do
        ollama["mistral"].should eq(32768)
      end

      it "includes codellama with 100000 tokens" do
        ollama["codellama"].should eq(100000)
      end

      it "has default of 4000" do
        ollama["default"].should eq(4000)
      end
    end

    context "google" do
      google = limits["google"].as(Hash(String, Int32))

      it "includes gemini-1.5-pro with 2097152 tokens" do
        google["gemini-1.5-pro"].should eq(2097152)
      end

      it "includes gemini-1.5-flash with 1048576 tokens" do
        google["gemini-1.5-flash"].should eq(1048576)
      end

      it "includes gemini-2.5-pro with 2000000 tokens" do
        google["gemini-2.5-pro"].should eq(2000000)
      end

      it "has default of 32760" do
        google["default"].should eq(32760)
      end
    end

    context "cohere" do
      cohere = limits["cohere"].as(Hash(String, Int32))

      it "includes command-r-plus with 256000 tokens" do
        cohere["command-r-plus"].should eq(256000)
      end

      it "includes command with 4096 tokens" do
        cohere["command"].should eq(4096)
      end

      it "has default of 4096" do
        cohere["default"].should eq(4096)
      end
    end

    context "vllm and lmstudio" do
      it "vllm has only default 4000" do
        limits["vllm"].as(Hash)["default"].should eq(4000)
      end

      it "lmstudio gpt-oss has 128000 tokens" do
        limits["lmstudio"].as(Hash)["gpt-oss"].should eq(128000)
      end

      it "lmstudio has default 4000" do
        limits["lmstudio"].as(Hash)["default"].should eq(4000)
      end
    end

    context "overall structure" do
      it "has top-level default of 4000" do
        limits["default"].should eq(4000)
      end

      it "contains all expected providers" do
        expected = %w[openai xai anthropic azure github ollama google cohere vllm lmstudio default]
        (limits.keys - expected).should be_empty
      end
    end
  end
end
