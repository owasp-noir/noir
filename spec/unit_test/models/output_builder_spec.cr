require "../../../src/models/output_builder.cr"
require "../../../src/options.cr"

describe "Initialize" do
  options = default_options
  options[:base] = "noir"
  options[:format] = "json"
  options[:output] = "output.json"

  it "OutputBuilder" do
    object = OutputBuilder.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderCommon" do
    object = OutputBuilderCommon.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderCurl" do
    object = OutputBuilderCurl.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderHttpie" do
    object = OutputBuilderHttpie.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderMarkdownTable" do
    object = OutputBuilderMarkdownTable.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderOas2" do
    object = OutputBuilderOas2.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderOas3" do
    object = OutputBuilderOas3.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderOnlyUrl" do
    object = OutputBuilderOnlyUrl.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderOnlyParam" do
    object = OutputBuilderOnlyParam.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderOnlyHeader" do
    object = OutputBuilderOnlyHeader.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderOnlyCookie" do
    object = OutputBuilderOnlyCookie.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderJsonl" do
    object = OutputBuilderJsonl.new options
    object.output_file.should eq("output.json")
  end
end

describe OutputBuilderDiff do
  options = default_options
  options[:base] = "noir"
  options[:format] = "json"

  it "calculates the diff correctly" do
    old_endpoints = [Endpoint.new("GET", "/old")]
    new_endpoints = [Endpoint.new("GET", "/new")]
    builder = OutputBuilderDiff.new options

    result = builder.diff(new_endpoints, old_endpoints)

    result[:added].should eq [Endpoint.new("GET", "/new")]
    result[:removed].should eq [Endpoint.new("GET", "/old")]
  end
end
