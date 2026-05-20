require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect AsyncAPI Docs" do
  options = create_test_options
  instance = Detector::Specification::AsyncApi.new options

  it "detects asyncapi 2.x json" do
    content = <<-JSON
      {
        "asyncapi": "2.6.0",
        "info": { "title": "t", "version": "1" }
      }
      JSON

    instance.detect("doc.json", content).should be_true
  end

  it "detects asyncapi 3.x yaml" do
    content = <<-YAML
      asyncapi: 3.0.0
      info:
        title: t
        version: 1
      YAML

    instance.detect("doc.yml", content).should be_true
  end

  it "ignores non-asyncapi yaml" do
    content = <<-YAML
      openapi: 3.0.0
      info:
        title: t
      YAML

    instance.detect("doc.yml", content).should be_false
  end

  it "registers path in code_locator" do
    content = <<-JSON
      {
        "asyncapi": "3.0.0",
        "info": { "title": "t", "version": "1" }
      }
      JSON

    locator = CodeLocator.instance
    locator.clear "asyncapi-json"
    instance.detect("doc.json", content)
    locator.all("asyncapi-json").should eq(["doc.json"])
  end
end
