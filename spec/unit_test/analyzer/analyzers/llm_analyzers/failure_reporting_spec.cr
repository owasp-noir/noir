require "../../../../spec_helper"
require "../../../../../src/analyzer/analyzers/llm_analyzers/unified_ai"
require "../../../../../src/models/skipped_files"
require "file_utils"

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

# Answers with a fixed reply and counts how often it was actually asked.
private class FixedReplyAdapter
  include LLM::Adapter

  getter calls = 0

  def initialize(@reply : String)
  end

  def request_messages(messages : Messages, format : String = "json") : String
    @calls += 1
    @reply
  end

  def request(prompt : String, format : String = "json") : String
    request_messages([] of Hash(String, String), format)
  end
end

private def with_isolated_llm_cache(&)
  prev_home = ENV["NOIR_HOME"]?
  prev_disable = ENV["NOIR_CACHE_DISABLE"]?
  tmp = File.tempname("noir-ai-reply-spec")
  Dir.mkdir_p(tmp)
  ENV["NOIR_HOME"] = tmp
  ENV.delete("NOIR_CACHE_DISABLE")
  Noir::SkippedFiles.clear
  begin
    yield
  ensure
    Noir::SkippedFiles.clear
    prev_home ? (ENV["NOIR_HOME"] = prev_home) : ENV.delete("NOIR_HOME")
    prev_disable ? (ENV["NOIR_CACHE_DISABLE"] = prev_disable) : ENV.delete("NOIR_CACHE_DISABLE")
    FileUtils.rm_rf(tmp)
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
  prev_disable = ENV["NOIR_CACHE_DISABLE"]?
  ENV["NOIR_CACHE_DISABLE"] = "1"
  Noir::SkippedFiles.clear
  begin
    yield
  ensure
    Noir::SkippedFiles.clear
    if prev_disable
      ENV["NOIR_CACHE_DISABLE"] = prev_disable
    else
      ENV.delete("NOIR_CACHE_DISABLE")
    end
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

  describe "an unusable LLM reply" do
    # A reply the analyzer cannot read used to fail its parse with a debug
    # line only, so the scan reported `errors: []` and exited 0 under
    # --strict. It was also cached, so every later scan replayed it.
    {
      "truncated"         => %({"endpoints":[{"url":"/users","method":"GET"},{"url":"/ord),
      "null"              => "null",
      "a string list"     => %({"endpoints":"none"}),
      "an error object"   => %({"error":"context length exceeded"}),
      "another key"       => %({"result":[]}),
      "a renamed list"    => %({"routes":[{"url":"/a","method":"GET"}]}),
      "a bare array"      => %(Answer: [{"url":"/a","method":"GET"}]),
      "a preamble+cutoff" => %({"thought":"scanning"} {"endpoints":[{"url":"/a"},{"url":"/b),
      "prose without one" => "I could not find any endpoints.",
    }.each do |label, reply|
      it "is reported as lost coverage when it is #{label}" do
        without_llm_cache do
          bundle = LLM::Bundle.new("- File: \"a.rb\"\n```\nget '/a'\n```\n", 300, ["a.rb"])
          ai_analyzer.__test_process_bundle(bundle, FixedReplyAdapter.new(reply))

          Noir::SkippedFiles.failures.map(&.message).join.should contain("a.rb")
        end
      end
    end

    it "is not cached, so the next scan asks again" do
      [%({"endpoints":[{"url":"/a"), %({"error":"context length exceeded"})].each do |reply|
        with_isolated_llm_cache do
          bundle = LLM::Bundle.new("- File: \"a.rb\"\n```\nget '/a'\n```\n", 300, ["a.rb"])
          adapter = FixedReplyAdapter.new(reply)
          ai_analyzer.__test_process_bundle(bundle, adapter)
          ai_analyzer.__test_process_bundle(bundle, adapter)
          adapter.calls.should eq(2)
        end
      end
    end

    it "finds the answer after a complete preamble object" do
      without_llm_cache do
        analyzer = ai_analyzer
        bundle = LLM::Bundle.new("- File: \"a.rb\"\n```\nget '/a'\n```\n", 300, ["a.rb"])
        analyzer.__test_process_bundle(bundle, FixedReplyAdapter.new(%({"thought":"scanning"} {"endpoints":[{"url":"/a","method":"GET"}]})))

        analyzer.__test_result.map(&.url).should eq(["/a"])
        Noir::SkippedFiles.failures.should be_empty
      end
    end

    it "uses the JSON a reply wraps in prose and a fence, and caches it" do
      with_isolated_llm_cache do
        bundle = LLM::Bundle.new("- File: \"a.rb\"\n```\nget '/a'\n```\n", 300, ["a.rb"])
        adapter = FixedReplyAdapter.new("Here you go:\n```json\n{\"endpoints\":[{\"url\":\"/a\",\"method\":\"GET\"}]}\n```\nDone.")
        first = ai_analyzer
        first.__test_process_bundle(bundle, adapter)
        second = ai_analyzer
        second.__test_process_bundle(bundle, adapter)

        first.__test_result.map(&.url).should eq(["/a"])
        second.__test_result.map(&.url).should eq(["/a"])
        adapter.calls.should eq(1)
        Noir::SkippedFiles.failures.should be_empty
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

    it "reads an empty object or a null list as nothing found" do
      ["{}", %({"endpoints":null})].each do |reply|
        without_llm_cache do
          analyzer = ai_analyzer
          bundle = LLM::Bundle.new("- File: \"blank.rb\"\n```\n# nothing\n```\n", 300, ["blank.rb"])

          analyzer.__test_process_bundle(bundle, FixedReplyAdapter.new(reply))

          Noir::SkippedFiles.failures.should be_empty
          analyzer.__test_result.should be_empty
        end
      end
    end
  end
end

# Overflows on any request carrying more than one file section and answers
# the rest with one endpoint per file, so the spec can see coverage survive.
private class OverflowAdapter
  include LLM::Adapter

  getter overflows = 0

  def initialize(@always : Bool = false)
  end

  def request_messages(messages : Messages, format : String = "json") : String
    ""
  end

  def request(prompt : String, format : String = "json") : String
    ""
  end

  def request_bundle(system : String, user : String, format : String) : String
    files = user.scan(/- File: "([^"]+)"/).map { |m| File.basename(m[1]) }
    if @always || files.size > 1
      @overflows += 1
      raise LLM::ContextOverflow.new(nil)
    end
    %({"endpoints":[{"url":"/ep/#{files[0]}","method":"GET","params":[]}]})
  end
end

# Overflows on any prompt over `max_chars` and records the routes it was shown.
private class SizeCapAdapter
  include LLM::Adapter

  getter seen = Set(String).new

  def initialize(@max_chars : Int32)
  end

  def request_messages(messages : Messages, format : String = "json") : String
    ""
  end

  def request(prompt : String, format : String = "json") : String
    ""
  end

  def request_bundle(system : String, user : String, format : String) : String
    raise LLM::ContextOverflow.new if user.size > @max_chars
    user.scan(/get '(\/r\d+)'/).each { |m| @seen << m[1] }
    %({"endpoints":[]})
  end
end

describe "Analyzer::AI::Unified on a context overflow" do
  it "re-splits one part of a split file without resending the other parts" do
    without_llm_cache do
      dir = File.tempname("noir-overflow-spec")
      Dir.mkdir_p(dir)
      begin
        path = File.join(dir, "routes.rb")
        File.write(path, (1..2000).map { |i| "get '/r#{i}'\n" }.join)
        parts = LLM.bundle_files([{path, File.read(path)}], 4000)
        parts.size.should be > 2
        own = parts[1].content.scan(/get '(\/r\d+)'/).map(&.[1]).to_set

        adapter = SizeCapAdapter.new(parts[1].content.size // 2 + 4000)
        ai_analyzer.__test_process_bundle(parts[1], adapter)

        adapter.seen.should eq(own)
        Noir::SkippedFiles.failures.should be_empty
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end

  it "re-splits the bundle instead of losing it" do
    without_llm_cache do
      dir = File.tempname("noir-overflow-spec")
      Dir.mkdir_p(dir)
      begin
        paths = %w[a.rb b.rb].map do |name|
          path = File.join(dir, name)
          File.write(path, "get '/x'\n" * 250)
          path
        end
        files = paths.map { |p| {p, File.read(p)} }
        bundle = LLM.bundle_files(files, 1_000_000)[0]

        analyzer = ai_analyzer
        adapter = OverflowAdapter.new
        analyzer.__test_process_bundle(bundle, adapter)

        analyzer.__test_result.map(&.url).uniq!.sort!.should eq(["/ep/a.rb", "/ep/b.rb"])
        Noir::SkippedFiles.failures.should be_empty
        adapter.overflows.should eq(1)
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end

  it "reports the files once re-splitting cannot help" do
    without_llm_cache do
      dir = File.tempname("noir-overflow-spec")
      Dir.mkdir_p(dir)
      begin
        path = File.join(dir, "a.rb")
        File.write(path, "get '/x'\n" * 250)
        bundle = LLM.bundle_files([{path, File.read(path)}], 1_000_000)[0]

        ai_analyzer.__test_process_bundle(bundle, OverflowAdapter.new(always: true))

        Noir::SkippedFiles.failures.map(&.message).join.should contain("context window")
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end
end
