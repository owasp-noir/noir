require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"

describe "Detect RAML" do
  options = create_test_options
  instance = Detector::Specification::RAML.new options

  it "raml" do
    instance.detect("app.yaml", "#%RAML\nApp: 1").should be_true
  end

  it "code_locator" do
    locator = CodeLocator.instance
    locator.clear "raml-spec"
    instance.detect("app.yaml", "#%RAML\nApp: 1")
    locator.all("raml-spec").should eq(["app.yaml"])
  end

  it "rejects yaml without the RAML header" do
    instance.detect("app.yaml", "App: 1").should be_false
  end

  it "rejects invalid yaml with the RAML header" do
    instance.detect("app.yaml", "#%RAML\nApp: [broken").should be_false
  end
end
