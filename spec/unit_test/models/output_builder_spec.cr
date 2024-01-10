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
end
