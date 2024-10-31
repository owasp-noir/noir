require "../../../../src/detector/detectors/*"
require "../../../../src/models/code_locator"

describe "Detect OAS 3.0 Docs" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Specification::Oas3.new options

  it "json format" do
    content = <<-EOS
    {
      "openapi": "3.0.0",
      "info": "test"
    }
    EOS

    instance.detect("docs.json", content).should eq(true)
  end
  it "yaml format" do
    content = <<-EOS
    openapi: 3.0.0
    info:
      version: 1.0.0
    EOS

    instance.detect("docs.yml", content).should eq(true)
  end

  it "code_locator" do
    content = <<-EOS
    {
      "openapi": "3.0.0",
      "info": "test"
    }
    EOS

    locator = CodeLocator.instance
    locator.clear "oas3-json"
    instance.detect("docs.json", content)
    locator.all("oas3-json").should eq(["docs.json"])
  end
end
