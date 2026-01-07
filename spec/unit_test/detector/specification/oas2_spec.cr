require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect OAS 2.0(Swagger) Docs" do
  options = create_test_options
  instance = Detector::Specification::Oas2.new options

  it "json format" do
    content = <<-JSON
      {
        "swagger": "2.0",
        "info": "test"
      }
      JSON

    instance.detect("docs.json", content).should be_true
  end
  it "yaml format" do
    content = <<-YAML
      swagger: "2.0"
      info:
        version: 1.0.0
      YAML

    instance.detect("docs.yml", content).should be_true
  end

  it "code_locator" do
    content = <<-JSON
      {
        "swagger": "2.0",
        "info": "test"
      }
      JSON

    locator = CodeLocator.instance
    locator.clear "swagger-json"
    instance.detect("docs.json", content)
    locator.all("swagger-json").should eq(["docs.json"])
  end
end
