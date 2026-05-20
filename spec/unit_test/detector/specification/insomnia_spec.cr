require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Insomnia Export" do
  options = create_test_options
  instance = Detector::Specification::Insomnia.new options

  it "v4 JSON format" do
    content = <<-JSON
      {
        "_type": "export",
        "__export_format": 4,
        "resources": []
      }
      JSON

    instance.detect("insomnia_v4.json", content).should be_true
  end

  it "v5 YAML format (collection)" do
    content = <<-YAML
      type: collection.insomnia.rest/5.0
      name: Sample
      collection: []
      YAML

    instance.detect("insomnia_v5.yaml", content).should be_true
  end

  it "v5 YAML format (spec)" do
    content = <<-YAML
      type: spec.insomnia.rest/5.0
      name: Sample
      collection: []
      YAML

    instance.detect("insomnia_v5.yaml", content).should be_true
  end

  it "code_locator (json)" do
    content = <<-JSON
      {
        "_type": "export",
        "__export_format": 4,
        "resources": []
      }
      JSON

    locator = CodeLocator.instance
    locator.clear "insomnia-json"
    instance.detect("test.json", content)
    locator.all("insomnia-json").should eq(["test.json"])
  end

  it "code_locator (yaml)" do
    content = <<-YAML
      type: collection.insomnia.rest/5.0
      name: Sample
      collection: []
      YAML

    locator = CodeLocator.instance
    locator.clear "insomnia-yaml"
    instance.detect("test.yaml", content)
    locator.all("insomnia-yaml").should eq(["test.yaml"])
  end

  it "invalid JSON is ignored" do
    content = <<-JSON
      {
        "_type": "workspace",
        "name": "not an export"
      }
      JSON

    instance.detect("not_insomnia.json", content).should be_false
  end

  it "non-insomnia YAML is ignored" do
    content = <<-YAML
      type: something.else/1.0
      name: Other
      YAML

    instance.detect("other.yaml", content).should be_false
  end
end
