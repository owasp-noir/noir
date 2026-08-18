require "../../../../spec_helper"
require "../../../../../src/analyzer/analyzers/llm_analyzers/unified_ai"
require "../../../../../src/models/skipped_files"

# Every adapter maps a call it could not complete — an HTTP error the retries
# did not clear, a provider error body, a dead ACP agent — to "". That empty
# string used to travel back through the analyzer's *success* path: the parse
# failed, a debug line was written, and the scan reported `errors: []` and
# exited 0 even under `--strict`. A provider answering HTTP 500 to every
# request was byte-identical to a clean scan of a codebase with no endpoints.
private class DeadAdapter
  include LLM::Adapter

  def request_messages(messages : Messages, format : String = "json") : String
    ""
  end

  def request(prompt : String, format : String = "json") : String
    ""
  end
end

private class WorkingAdapter
  include LLM::Adapter

  def request_messages(messages : Messages, format : String = "json") : String
    %({"endpoints":[{"url":"/ai/found","method":"GET","params":[]}]})
  end

  def request(prompt : String, format : String = "json") : String
    request_messages([] of Hash(String, String), format)
  end
end

private class EmptyResultAdapter
  include LLM::Adapter

  def request_messages(messages : Messages, format : String = "json") : String
    %({"endpoints":[]})
  end

  def request(prompt : String, format : String = "json") : String
    request_messages([] of Hash(String, String), format)
  end
end

class Analyzer::AI::Unified
  def __test_process_bundle(bundle : LLM::Bundle, adapter : LLM::Adapter)
    process_bundle(bundle, adapter)
  end

  def __test_result : Array(Endpoint)
    @result
  end
end

private def ai_analyzer : Analyzer::AI::Unified
  Analyzer::AI::Unified.new(Hash{
    "url"         => YAML::Any.new(""),
    "debug"       => YAML::Any.new(false),
    "verbose"     => YAML::Any.new(false),
    "color"       => YAML::Any.new(false),
    "nolog"       => YAML::Any.new(true),
    "ai_provider" => YAML::Any.new("http://127.0.0.1:1/v1"),
    "ai_model"    => YAML::Any.new("test-model"),
    "base"        => YAML::Any.new([YAML::Any.new(".")]),
  })
end

private def without_llm_cache(&)
  LLM::Cache.disable
  Noir::SkippedFiles.clear
  begin
    yield
  ensure
    Noir::SkippedFiles.clear
    LLM::Cache.enable
  end
end

describe Analyzer::AI::Unified do
  describe "a failed LLM call" do
    it "is reported as lost coverage for every file the bundle carried" do
      without_llm_cache do
        bundle = LLM::Bundle.new("- File: \"a.rb\"\n```\nget '/a'\n```\n", 300, ["a.rb", "b.rb"])
        ai_analyzer.__test_process_bundle(bundle, DeadAdapter.new)

        failures = Noir::SkippedFiles.failures
        failures.size.should eq(1)
        failures[0].tech.should eq("ai")
        failures[0].message.should contain("a.rb")
        failures[0].message.should contain("b.rb")
        failures[0].message.should contain("no usable response")
      end
    end

    it "leaves the endpoints of the bundles that did succeed alone" do
      without_llm_cache do
        analyzer = ai_analyzer
        good = LLM::Bundle.new("- File: \"ok.rb\"\n```\nget '/ok'\n```\n", 300, ["ok.rb"])
        bad = LLM::Bundle.new("- File: \"bad.rb\"\n```\nget '/bad'\n```\n", 300, ["bad.rb"])

        analyzer.__test_process_bundle(good, WorkingAdapter.new)
        analyzer.__test_process_bundle(bad, DeadAdapter.new)

        analyzer.__test_result.map(&.url).should eq(["/ai/found"])
        Noir::SkippedFiles.failures.map(&.message).join.should contain("bad.rb")
        Noir::SkippedFiles.failures.map(&.message).join.should_not contain("ok.rb")
      end
    end
  end

  describe "a successful LLM call" do
    it "reports no failure at all, so --strict still passes" do
      without_llm_cache do
        analyzer = ai_analyzer
        bundle = LLM::Bundle.new("- File: \"ok.rb\"\n```\nget '/ok'\n```\n", 300, ["ok.rb"])

        analyzer.__test_process_bundle(bundle, WorkingAdapter.new)

        Noir::SkippedFiles.failures.should be_empty
        analyzer.__test_result.size.should eq(1)
      end
    end

    it "reports no failure when the model legitimately finds nothing" do
      # An empty *endpoints list* is a real answer and must stay
      # distinguishable from an empty *response*.
      without_llm_cache do
        analyzer = ai_analyzer
        bundle = LLM::Bundle.new("- File: \"blank.rb\"\n```\n# nothing\n```\n", 300, ["blank.rb"])

        analyzer.__test_process_bundle(bundle, EmptyResultAdapter.new)

        Noir::SkippedFiles.failures.should be_empty
        analyzer.__test_result.should be_empty
      end
    end
  end
end
