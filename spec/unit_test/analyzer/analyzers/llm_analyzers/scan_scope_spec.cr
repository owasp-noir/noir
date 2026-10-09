require "../../../../spec_helper"
require "../../../../../src/analyzer/analyzers/llm_analyzers/unified_ai"

# Paths an LLM hands back are untrusted: the model is steered by the code it
# reads. Whatever it names, only files the detector registered — inside the
# scan base, past --exclude-path — may be read or reported.
private class ScriptedAdapter
  include LLM::Adapter

  def initialize(@reply : String)
  end

  def request_messages(messages : Messages, format : String = "json") : String
    @reply
  end

  def request(prompt : String, format : String = "json") : String
    @reply
  end
end

class Analyzer::AI::Unified
  def __test_filter_paths(all_paths : Array(String), adapter : LLM::Adapter) : Array(String)
    filter_paths_with_llm(all_paths, adapter)
  end
end

private def scope_analyzer(base : String) : Analyzer::AI::Unified
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(base)])
  options["ai_provider"] = YAML::Any.new("http://127.0.0.1:1/v1")
  options["ai_model"] = YAML::Any.new("test-model")
  options["ai_max_token"] = YAML::Any.new(4000)
  Analyzer::AI::Unified.new(options)
end

# A scan root with twelve in-scope files and one excluded secret that the
# detector never registered — the shape `--exclude-path 'vault/**'` leaves.
private def with_scoped_project(&)
  root = File.tempname("noir-ai-scope")
  prev_disable = ENV["NOIR_CACHE_DISABLE"]?
  ENV["NOIR_CACHE_DISABLE"] = "1"
  begin
    FileUtils.mkdir_p(File.join(root, "vault"))
    File.write(File.join(root, "vault", "keys.py"), %(API_KEY = "sk-live-VAULT-SECRET-123"))
    CodeLocator.instance.reset_files
    12.times do |i|
      path = File.join(root, "f#{i}.js")
      File.write(path, "app.get('/r#{i}', h)\n")
      CodeLocator.instance.register_path(path)
    end
    yield root
  ensure
    CodeLocator.instance.reset_files
    FileUtils.rm_rf(root)
    prev_disable ? (ENV["NOIR_CACHE_DISABLE"] = prev_disable) : ENV.delete("NOIR_CACHE_DISABLE")
  end
end

describe Analyzer::AI::Unified do
  describe "the LLM file filter" do
    it "drops a selected path that is not in the scanned file set" do
      with_scoped_project do |root|
        secret = File.join(root, "vault", "keys.py")
        kept = File.join(root, "f1.js")
        reply = {files: [secret, kept]}.to_json

        selected = scope_analyzer(root).__test_filter_paths(CodeLocator.instance.all_files, ScriptedAdapter.new(reply))
        selected.should eq([kept])
      end
    end

    it "falls back to every scanned file when the reply names only out-of-set paths" do
      with_scoped_project do |root|
        reply = {files: [File.join(root, "vault", "keys.py")]}.to_json

        selected = scope_analyzer(root).__test_filter_paths(CodeLocator.instance.all_files, ScriptedAdapter.new(reply))
        selected.size.should eq(12)
        selected.none?(&.includes?("vault")).should be_true
      end
    end
  end
end
