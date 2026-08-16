require "../../spec_helper"
require "../../../src/models/analyzer.cr"

class AnalyzerBasePathHarness < Analyzer
  def configured_base(path : String) : String
    configured_base_for(path)
  end
end

# Names itself the way a real analyzer does, so a skipped file can be
# attributed to a tech.
class AnalyzerSkipHarness < Analyzer
  analyzer_for "spec_skip_harness"

  def scan(files : Array(String), &block : String -> Nil)
    scan_files(files, &block)
  end

  def scan_via_workers(files : Array(String), &block : String -> Nil)
    parallel_analyze(files, &block)
  end
end

describe "Initialize Analyzer" do
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new("noir")])
  object = Analyzer.new(options)

  it "getter - url" do
    object.url.should eq("")
  end

  it "getter - result" do
    empty = [] of Endpoint
    object.result.should eq(empty)
  end

  it "initialized - base_path" do
    object.base_path.should eq("noir")
  end

  it "selects the most specific configured base path" do
    options = create_test_options
    options["base"] = YAML::Any.new([
      YAML::Any.new("spec/functional_test/fixtures"),
      YAML::Any.new("spec/functional_test/fixtures/python/robyn_multi_base/service_a"),
    ])
    harness = AnalyzerBasePathHarness.new(options)

    harness.configured_base("spec/functional_test/fixtures/python/robyn_multi_base/service_a/app.py").should eq("spec/functional_test/fixtures/python/robyn_multi_base/service_a")
  end

  it "matches files under the filesystem root base path" do
    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(File::SEPARATOR.to_s)])
    harness = AnalyzerBasePathHarness.new(options)

    harness.configured_base(File.join(Dir.current, "src/noir.cr")).should eq(File::SEPARATOR.to_s)
  end
end

describe "Initialize FileAnalyzer" do
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new("noir")])
  object = FileAnalyzer.new(options)

  it "getter - url" do
    object.url.should eq("")
  end

  it "getter - result" do
    empty = [] of Endpoint
    object.result.should eq(empty)
  end

  it "initialized - base_path" do
    object.base_path.should eq("noir")
  end

  it "getter - hooks_count" do
    object.hooks_count.should_not eq(0)
  end

  # Hooks that recognise an endpoint by matching against `-u/--url` cannot
  # do anything without one, but the url-independent hooks (graphql
  # operation documents) still have to run — a plain `noir scan ./app`
  # used to skip the file analyzer wholesale and lose them.
  it "keeps url-independent hooks active when no url is set" do
    object.url.should eq("")
    object.active_hooks.should_not be_empty
    object.active_hooks.all?(&.requires_url.!).should be_true
  end

  it "activates every hook once a url is set" do
    with_url = create_test_options
    with_url["base"] = YAML::Any.new([YAML::Any.new("noir")])
    with_url["url"] = YAML::Any.new("https://ex.com")

    analyzer = FileAnalyzer.new(with_url)
    analyzer.active_hooks.size.should be > object.active_hooks.size
  end

  # `noir scan` branches on this to decide whether a code base with zero
  # detected technologies is still worth an analysis pass. If it ever goes
  # false the CLI takes its "nothing left to do" exit and every
  # url-independent hook silently stops contributing to a default scan —
  # which is exactly the regression that made `.graphql`/`.gql` operation
  # documents invisible to `noir scan ./app`.
  it "reports that url-independent hooks exist" do
    FileAnalyzer.url_independent_hooks?.should be_true
  end
end

# One unreadable or unparsable file costs only itself — that is what the
# per-file rescues are for. But until they tallied it, the result of a scan
# that dropped a file was byte-identical to one that read everything, so the
# skip has to reach `Noir::SkippedFiles` and from there the `errors` array.
describe "Analyzer per-file skips" do
  before_each { Noir::SkippedFiles.clear }
  after_each { Noir::SkippedFiles.clear }

  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new("noir")])

  it "records a file whose analysis raised, and attributes it to the tech" do
    harness = AnalyzerSkipHarness.new(options)

    harness.scan(["a.cr", "b.cr"]) do |path|
      raise "boom on #{path}" if path == "a.cr"
    end

    Noir::SkippedFiles.count.should eq(1)
    failure = Noir::SkippedFiles.failures.first
    failure.tech.should eq("spec_skip_harness")
    failure.message.should contain("a.cr")
    failure.message.should contain("boom on a.cr")
  end

  it "records a skip from the bare worker loop too" do
    harness = AnalyzerSkipHarness.new(options)

    harness.scan_via_workers(["c.cr"]) { raise "worker boom" }

    Noir::SkippedFiles.count.should eq(1)
    Noir::SkippedFiles.failures.first.message.should contain("worker boom")
  end

  it "records nothing when every file is analyzed" do
    harness = AnalyzerSkipHarness.new(options)

    seen = [] of String
    harness.scan(["a.cr", "b.cr"]) { |path| seen << path }

    seen.sort.should eq(["a.cr", "b.cr"])
    Noir::SkippedFiles.count.should eq(0)
  end
end
