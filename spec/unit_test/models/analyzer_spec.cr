require "../../spec_helper"
require "../../../src/models/analyzer.cr"

class AnalyzerBasePathHarness < Analyzer
  def configured_base(path : String) : String
    configured_base_for(path)
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
end
