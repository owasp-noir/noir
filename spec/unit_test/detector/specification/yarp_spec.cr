require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect YARP reverse proxy config" do
  options = create_test_options
  instance = Detector::Specification::Yarp.new options

  it "detects the ReverseProxy section of appsettings.json" do
    CodeLocator.instance.clear Noir::LocatorKeys::YARP_SPEC
    content = %({\n  // comment\n  "ReverseProxy": {"Routes": {"r1": {"ClusterId": "c1", "Match": {"Path": "/a"}}}}\n})
    instance.detect("appsettings.json", content).should be_true
    CodeLocator.instance.all(Noir::LocatorKeys::YARP_SPEC).should eq(["appsettings.json"])
  end

  it "detects RouteMatch initializers in C#" do
    instance.detect("Program.cs", %(var m = new RouteMatch { Path = "/a" };)).should be_true
  end

  it "rejects a plain appsettings.json" do
    instance.detect("appsettings.json", %({"Logging": {"LogLevel": {"Default": "Information"}}})).should be_false
  end

  it "rejects an empty ReverseProxy section" do
    instance.detect("appsettings.json", %({"ReverseProxy": {"Clusters": {}}})).should be_false
  end

  it "rejects ASP.NET MVC RouteConfig" do
    instance.detect("RouteConfig.cs", %(public class RouteConfig { public static void RegisterRoutes(RouteCollection routes) {} })).should be_false
  end
end
