require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Postman Collection" do
  options = create_test_options
  instance = Detector::Specification::Postman.new options

  it "v2.1.0 format" do
    content = <<-JSON
      {
        "info": {
          "_postman_id": "12345678-1234-1234-1234-123456789012",
          "name": "Sample API",
          "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
        },
        "item": []
      }
      JSON

    instance.detect("collection.json", content).should be_true
  end

  it "v2.0.0 format" do
    content = <<-JSON
      {
        "info": {
          "name": "Sample API",
          "schema": "https://schema.getpostman.com/json/collection/v2.0.0/collection.json"
        },
        "item": []
      }
      JSON

    instance.detect("collection.json", content).should be_true
  end

  it "code_locator" do
    content = <<-JSON
      {
        "info": {
          "name": "Test Collection",
          "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
        },
        "item": []
      }
      JSON

    locator = CodeLocator.instance
    locator.clear "postman-json"
    instance.detect("test.json", content)
    locator.all("postman-json").should eq(["test.json"])
  end

  it "invalid format" do
    content = <<-JSON
      {
        "info": {
          "name": "Not a Postman Collection"
        },
        "item": []
      }
      JSON

    instance.detect("not_postman.json", content).should be_false
  end
end
