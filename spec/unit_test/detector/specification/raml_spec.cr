require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"

describe "Detect RAML" do
  options = create_test_options
  instance = Detector::Specification::RAML.new options

  it "raml" do
    instance.detect("app.yaml", "#%RAML\nApp: 1").should eq(true)
  end

  it "code_locator" do
    locator = CodeLocator.instance
    locator.clear "raml-spec"
    instance.detect("app.yaml", "#%RAML\nApp: 1")
    locator.all("raml-spec").should eq(["app.yaml"])
  end
end
