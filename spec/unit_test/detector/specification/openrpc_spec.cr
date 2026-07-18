require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect OpenRPC Docs" do
  options = create_test_options
  instance = Detector::Specification::OpenRpc.new options

  it "detects openrpc 1.x json" do
    content = <<-JSON
      {
        "openrpc": "1.2.6",
        "info": { "title": "t", "version": "1" },
        "methods": []
      }
      JSON

    instance.detect("openrpc.json", content).should be_true
  end

  it "ignores an openapi document" do
    content = <<-JSON
      {
        "openapi": "3.0.0",
        "info": { "title": "t" }
      }
      JSON

    instance.detect("doc.json", content).should be_false
  end

  it "ignores yaml files" do
    content = <<-YAML
      openrpc: 1.2.6
      info:
        title: t
      YAML

    instance.detect("doc.yml", content).should be_false
  end

  it "registers path in code_locator" do
    content = <<-JSON
      {
        "openrpc": "1.2.6",
        "info": { "title": "t", "version": "1" },
        "methods": []
      }
      JSON

    locator = CodeLocator.instance
    locator.clear "openrpc-json"
    instance.detect("openrpc.json", content)
    locator.all("openrpc-json").should eq(["openrpc.json"])
  end
end
