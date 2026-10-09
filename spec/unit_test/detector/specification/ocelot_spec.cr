require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Ocelot gateway config" do
  options = create_test_options
  instance = Detector::Specification::Ocelot.new options

  it "detects ocelot.json routes and registers the path" do
    CodeLocator.instance.clear Noir::LocatorKeys::OCELOT_SPEC
    content = %({"Routes": [{"UpstreamPathTemplate": "/a", "DownstreamPathTemplate": "/b"}]})
    instance.detect("ocelot.json", content).should be_true
    CodeLocator.instance.all(Noir::LocatorKeys::OCELOT_SPEC).should eq(["ocelot.json"])
  end

  it "detects legacy ReRoutes with comments" do
    content = %({\n  // old Ocelot\n  "ReRoutes": [{"UpstreamPathTemplate": "/a",}]\n})
    instance.detect("ocelot.Production.json", content).should be_true
  end

  it "rejects JSON that only mentions the key" do
    instance.detect("notes.json", %({"doc": "UpstreamPathTemplate"})).should be_false
  end

  it "rejects appsettings without Ocelot routes" do
    instance.detect("appsettings.json", %({"Logging": {"LogLevel": {"Default": "Information"}}})).should be_false
  end
end
