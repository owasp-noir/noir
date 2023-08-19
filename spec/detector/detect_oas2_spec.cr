require "../../src/detector/detectors/*"
require "../../src/models/code_locator"

describe "Detect OAS 2.0(Swagger) Docs" do
  options = default_options()
  instance = DetectorOas2.new options

  it "json format" do
    content = <<-EOS
    {
      "swagger": "2.0",
      "info": "test"
    }
    EOS

    instance.detect("docs.json", content).should eq(true)
  end
  it "yaml format" do
    content = <<-EOS
    swagger: "2.0"
    info:
      version: 1.0.0
    EOS

    instance.detect("docs.yml", content).should eq(true)
  end

  it "code_locator" do
    content = <<-EOS
    {
      "swagger": "2.0",
      "info": "test"
    }
    EOS

    instance.detect("docs.json", content)
    locator = CodeLocator.instance
    locator.get("swagger-json").should eq("docs.json")
  end
end
