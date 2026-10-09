require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Hoppscotch Collection" do
  options = create_test_options
  instance = Detector::Specification::Hoppscotch.new options
  locator = CodeLocator.instance

  collection = <<-JSON
    {"v": 2, "name": "My API", "folders": [], "requests": [
      {"v": "4", "method": "GET", "endpoint": "https://api.example.com/users/1"}
    ]}
    JSON

  it "detects and registers a collection export" do
    locator.clear Noir::LocatorKeys::HOPPSCOTCH_JSON
    instance.detect("my-api.json", collection).should be_true
    locator.all(Noir::LocatorKeys::HOPPSCOTCH_JSON).should eq(["my-api.json"])
  end

  it "detects an all-collections array export" do
    instance.detect("all.json", "[#{collection}]").should be_true
  end

  it "rejects JSON without the collection shape" do
    instance.detect("job.json", %({"name": "x", "requests": [{"method": "GET", "endpoint": "/a"}]})).should be_false
    instance.detect("job.json", %({"v": 1, "folders": [], "requests": [{"url": "/a"}]})).should be_false
    instance.detect("my-api.txt", collection).should be_false
  end

  it "registers an environment export without reporting the tech" do
    locator.clear Noir::LocatorKeys::HOPPSCOTCH_JSON
    env = %({"name": "Dev", "variables": [{"key": "baseUrl", "value": "https://x/v1", "secret": false}]})
    instance.detect("env.json", env).should be_false
    locator.all(Noir::LocatorKeys::HOPPSCOTCH_JSON).should eq(["env.json"])
  end

  it "ignores a key/value list without the secret flag" do
    locator.clear Noir::LocatorKeys::HOPPSCOTCH_JSON
    instance.detect("vars.json", %({"name": "x", "variables": [{"key": "a", "value": "b"}]})).should be_false
    locator.all(Noir::LocatorKeys::HOPPSCOTCH_JSON).should be_empty
  end
end
