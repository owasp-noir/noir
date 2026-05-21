require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Azure Functions function.json" do
  options = create_test_options
  instance = Detector::Specification::AzureFunctions.new options

  it "detects function.json with httpTrigger binding" do
    src = %({"bindings":[{"type":"httpTrigger","direction":"in","methods":["get"]}]})
    locator = CodeLocator.instance
    locator.clear "azure-functions-spec"

    instance.detect("MyFunc/function.json", src).should be_true
    locator.all("azure-functions-spec").should eq ["MyFunc/function.json"]
  end

  it "rejects function.json without httpTrigger" do
    src = %({"bindings":[{"type":"queueTrigger"}]})
    instance.detect("Worker/function.json", src).should be_false
  end

  it "ignores unrelated filenames" do
    instance.detect("config.json", %({"bindings":[{"type":"httpTrigger"}]})).should be_false
  end
end
