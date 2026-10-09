require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Hurl Files" do
  options = create_test_options
  instance = Detector::Specification::Hurl.new options

  it "detects a .hurl file with a request line" do
    content = <<-HURL
      GET https://example.org/api/health
      HTTP 200
      HURL

    instance.detect("api.hurl", content).should be_true
  end

  it "detects a templated host" do
    instance.detect("api.hurl", "POST {{host}}/login\n").should be_true
  end

  it "ignores other extensions" do
    instance.detect("api.http", "GET https://example.org/\n").should be_false
  end

  it "ignores lowercase prose" do
    instance.detect("notes.hurl", "get started with hurl\n").should be_false
  end

  it "registers the path in the code locator" do
    locator = CodeLocator.instance
    locator.clear Noir::LocatorKeys::HURL_FILE
    instance.detect("health.hurl", "GET https://example.org/health\n")
    locator.all(Noir::LocatorKeys::HURL_FILE).should eq(["health.hurl"])
  end
end
