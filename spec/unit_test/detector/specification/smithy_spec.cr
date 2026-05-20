require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"

describe "Detect Smithy" do
  options = create_test_options
  instance = Detector::Specification::Smithy.new options

  it "smithy" do
    instance.detect("service.smithy", "$version: \"2\"\nnamespace example\n").should be_true
  end

  it "rejects non-smithy extension" do
    instance.detect("service.proto", "$version: \"2\"\n").should be_false
  end

  it "rejects smithy file without version header" do
    instance.detect("service.smithy", "namespace example\n").should be_false
  end

  it "code_locator" do
    locator = CodeLocator.instance
    locator.clear "smithy-spec"
    instance.detect("service.smithy", "$version: \"2\"\n")
    locator.all("smithy-spec").should eq(["service.smithy"])
  end
end
