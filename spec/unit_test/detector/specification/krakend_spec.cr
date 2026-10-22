require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect KrakenD config" do
  options = create_test_options
  instance = Detector::Specification::Krakend.new options

  it "detects krakend.json and registers the path" do
    CodeLocator.instance.clear Noir::LocatorKeys::KRAKEND_SPEC
    content = %({"version": 3, "endpoints": [{"endpoint": "/a", "backend": [{"url_pattern": "/a"}]}]})
    instance.detect("krakend.json", content).should be_true
    CodeLocator.instance.all(Noir::LocatorKeys::KRAKEND_SPEC).should eq(["krakend.json"])
  end

  it "rejects endpoints without backends" do
    instance.detect("config.json", %({"version": 1, "endpoints": [{"endpoint": "/a"}], "backend": "x"})).should be_false
  end

  it "rejects documents without a version" do
    instance.detect("config.json", %({"endpoints": [{"endpoint": "/a", "backend": []}]})).should be_false
  end
end
