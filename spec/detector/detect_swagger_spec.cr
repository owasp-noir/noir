require "../../src/detector/detectors/*"

describe "Detect Swagger Docs" do
  options = default_options()
  instance = DetectorSwagger.new options

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
end
