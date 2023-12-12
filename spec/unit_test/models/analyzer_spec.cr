require "../../../src/models/analyzer.cr"
require "../../../src/options.cr"

describe "Initialize Analyzer" do
  options = default_options
  options[:base] = "noir"
  object = Analyzer.new(options)

  it "getter - url" do
    object.url.should eq("")
  end

  it "getter - scope" do
    object.scope.should eq("url,param")
  end

  it "getter - result" do
    empty = [] of Endpoint
    object.result.should eq(empty)
  end

  it "initialized - base_path" do
    object.base_path.should eq("noir")
  end
end

describe "Initialize FileAnalyzer" do
  options = default_options
  options[:base] = "noir"
  object = FileAnalyzer.new(options)

  it "getter - url" do
    object.url.should eq("")
  end

  it "getter - scope" do
    object.scope.should eq("url,param")
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