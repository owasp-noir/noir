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

  def __test_bundle_paths(labels : Array(String), reply : String) : Array(Array(String))
    process_bundle(LLM::Bundle.new("app.get('/x', h)", 10, labels), ScriptedAdapter.new(reply))
    @result.map(&.details.code_paths.map(&.path))
  end

  def __test_select_target_paths(adapter : LLM::Adapter) : Array(String)
    select_target_paths(adapter)
  end

  def __test_bundle_labels(paths : Array(String)) : Array(String)
    prepare_files_for_bundling(paths).map(&.[0])
  end

  def __test_resolve(file : String) : String?
    resolve_reported_file(file)
  end

  def __test_agent_paths(reply : String) : Array(Array(String))
    apply_agent_finalize(JSON.parse(reply))
    @result.map(&.details.code_paths.map(&.path))
  end
end

private def endpoint_reply(file : String) : String
  {endpoints: [{url: "/x", method: "GET", file: file, line: 1}]}.to_json
end

private def scope_analyzer(*bases : String) : Analyzer::AI::Unified
  options = create_test_options
  options["base"] = YAML::Any.new(bases.map { |base| YAML::Any.new(base) }.to_a)
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
  describe "--ai-scope unmatched" do
    it "skips files a static analyzer already found endpoints in" do
      with_scoped_project do |root|
        options = create_test_options
        options["base"] = YAML::Any.new([YAML::Any.new(root)])
        options["ai_provider"] = YAML::Any.new("http://127.0.0.1:1/v1")
        options["ai_model"] = YAML::Any.new("test-model")
        covered = (0..10).map { |i| YAML::Any.new(File.join(root, "f#{i}.js")) }
        options[Analyzer::AI::Unified::COVERED_FILES_OPTION] = YAML::Any.new(covered)

        analyzer = Analyzer::AI::Unified.new(options)
        analyzer.__test_select_target_paths(ScriptedAdapter.new("{}")).should eq([File.join(root, "f11.js")])
      end
    end
  end

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

    it "keeps credentials files out of the selection and the bundles" do
      with_scoped_project do |root|
        env = File.join(root, ".env")
        File.write(env, "SECRET=1")
        CodeLocator.instance.register_path(env)
        reply = {files: [env, File.join(root, "f1.js")]}.to_json

        analyzer = scope_analyzer(root)
        analyzer.__test_filter_paths(CodeLocator.instance.all_files, ScriptedAdapter.new(reply)).should eq([File.join(root, "f1.js")])
        analyzer.__test_bundle_labels([env, File.join(root, "f2.js")]).should eq(["f2.js"])
      end
    end
  end

  describe "an endpoint's reported file" do
    it "resolves a base-relative name to the scanned path" do
      with_scoped_project do |root|
        paths = scope_analyzer(root).__test_bundle_paths(["f0.js"], endpoint_reply("f3.js"))
        paths.should eq([[File.join(root, "f3.js")]])
      end
    end

    it "is replaced by the bundle's own file when it escapes the scan" do
      with_scoped_project do |root|
        outside = File.tempname("noir-ai-outside")
        File.write(outside, "AWS_SECRET_ACCESS_KEY=top-secret")
        link = File.join(root, "link.js")
        File.symlink(outside, link)
        CodeLocator.instance.register_path(link)
        begin
          fallback = [[File.join(root, "f0.js")]]
          [
            "../#{File.basename(outside)}", # parent traversal
            outside,                        # absolute, outside the base
            "vault/keys.py",                # in the base, but excluded
            "link.js",                      # in the base, links outside
            "missing.js",                   # hallucinated
          ].each do |file|
            scope_analyzer(root).__test_bundle_paths(["f0.js"], endpoint_reply(file)).should eq(fallback)
          end
        ensure
          File.delete(outside)
        end
      end
    end

    it "gives no code path when it does not resolve in a multi-file bundle" do
      with_scoped_project do |root|
        scope_analyzer(root).__test_bundle_paths(["f0.js", "f1.js"], endpoint_reply("missing.js")).should eq([[] of String])
      end
    end

    it "maps each bundle label back to its own base's file when several bases share names" do
      with_scoped_project do |root|
        a = File.join(root, "a", "app0.js")
        b = File.join(root, "b", "app0.js")
        [a, b].each do |path|
          Dir.mkdir_p(File.dirname(path))
          File.write(path, "app.get('/x', h)\n")
          CodeLocator.instance.register_path(path)
        end

        analyzer = scope_analyzer(File.join(root, "a"), File.join(root, "b"))
        labels = analyzer.__test_bundle_labels([a, b])
        labels.uniq.size.should eq(2)
        labels.map { |label| analyzer.__test_resolve(label) }.should eq([a, b])
        # A bare name both bases hold is ambiguous, not a coin flip.
        analyzer.__test_resolve("app0.js").should be_nil
      end
    end

    it "leaves an agent endpoint without a code path rather than a fake one" do
      with_scoped_project do |root|
        reply = {endpoints: [{url: "/x", method: "GET", file: "../etc/passwd"}]}.to_json
        scope_analyzer(root).__test_agent_paths(reply).should eq([[] of String])
      end
    end
  end
end
