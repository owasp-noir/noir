require "../../../src/models/output_builder.cr"
require "../../../src/options.cr"

describe "Initialize" do
  options = default_options
  options[:base] = "noir"
  options[:scope] = "param"

  it "OutputBuilder" do
    object = OutputBuilder.new options
    object.scope.should eq("param")
  end

  it "OutputBuilderCommon" do
    object = OutputBuilderCommon.new options
    object.scope.should eq("param")
  end

  it "OutputBuilderCurl" do
    object = OutputBuilderCurl.new options
    object.scope.should eq("param")
  end

  it "OutputBuilderHttpie" do
    object = OutputBuilderHttpie.new options
    object.scope.should eq("param")
  end

  it "OutputBuilderMarkdownTable" do
    object = OutputBuilderMarkdownTable.new options
    object.scope.should eq("param")
  end

  it "OutputBuilderOas2" do
    object = OutputBuilderOas2.new options
    object.scope.should eq("param")
  end

  it "OutputBuilderOas3" do
    object = OutputBuilderOas3.new options
    object.scope.should eq("param")
  end
end
