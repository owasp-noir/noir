require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Postman Collection" do
  options = create_test_options
  instance = Detector::Specification::Postman.new options

  it "v2.1.0 format" do
    content = <<-EOS
    {
      "info": {
        "_postman_id": "12345678-1234-1234-1234-123456789012",
        "name": "Sample API",
        "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
      },
      "item": []
    }
    EOS

    instance.detect("collection.json", content).should be_true
  end

  it "v2.0.0 format" do
    content = <<-EOS
    {
      "info": {
        "name": "Sample API",
        "schema": "https://schema.getpostman.com/json/collection/v2.0.0/collection.json"
      },
      "item": []
    }
    EOS

    instance.detect("collection.json", content).should be_true
  end

  it "code_locator" do
    content = <<-EOS
    {
      "info": {
        "name": "Test Collection",
        "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
      },
      "item": []
    }
    EOS

    locator = CodeLocator.instance
    locator.clear "postman-json"
    instance.detect("test.json", content)
    locator.all("postman-json").should eq(["test.json"])
  end

  it "invalid format" do
    content = <<-EOS
    {
      "info": {
        "name": "Not a Postman Collection"
      },
      "item": []
    }
    EOS

    instance.detect("not_postman.json", content).should be_false
  end
end
