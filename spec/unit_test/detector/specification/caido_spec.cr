require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Caido Export" do
  options = create_test_options
  instance = Detector::Specification::Caido.new options

  it "detects Caido JSON export" do
    content = <<-JSON
      [
        {
          "id": 1,
          "host": "www.example.com",
          "method": "GET",
          "path": "/",
          "is_tls": true,
          "port": 443,
          "raw": "R0VUIC8gSFRUUC8xLjENCg0K",
          "response": { "id": 1, "status_code": 200, "raw": "" }
        }
      ]
      JSON

    instance.detect("caido_export.json", content).should be_true
  end

  it "registers the export path in CodeLocator" do
    content = <<-JSON
      [
        {
          "host": "www.example.com",
          "method": "GET",
          "path": "/",
          "is_tls": false,
          "port": 80,
          "raw": "R0VUIC8gSFRUUC8xLjENCg0K"
        }
      ]
      JSON

    locator = CodeLocator.instance
    locator.clear "caido-json"
    instance.detect("test_caido.json", content)
    locator.all("caido-json").should eq(["test_caido.json"])
  end

  it "rejects HAR files" do
    content = <<-JSON
      {
        "log": {
          "version": "1.2",
          "entries": []
        }
      }
      JSON

    instance.detect("trace.har", content).should be_false
    instance.detect("trace.json", content).should be_false
  end

  it "rejects Postman collections" do
    content = <<-JSON
      {
        "info": { "name": "My Collection", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json" },
        "item": []
      }
      JSON

    instance.detect("postman.json", content).should be_false
  end

  it "rejects Insomnia exports" do
    content = <<-JSON
      {
        "_type": "export",
        "__export_format": 4,
        "resources": []
      }
      JSON

    instance.detect("insomnia.json", content).should be_false
  end

  it "rejects empty arrays" do
    instance.detect("empty.json", "[]").should be_false
  end

  it "rejects arrays missing the Caido signature" do
    content = <<-JSON
      [
        { "url": "https://example.com", "method": "GET" }
      ]
      JSON

    instance.detect("other.json", content).should be_false
  end

  it "rejects non-JSON files" do
    instance.detect("notes.txt", "[1,2,3]").should be_false
  end
end
