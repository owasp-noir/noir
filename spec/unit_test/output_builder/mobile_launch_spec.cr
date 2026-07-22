require "../../spec_helper"
require "../../../src/output_builder/mobile_launch"

private struct MobileLaunchTestHelper
  include MobileLaunch
end

describe MobileLaunch do
  helper = MobileLaunchTestHelper.new

  describe "#ios_origin?" do
    it "returns true for technology 'ios'" do
      ep = Endpoint.new("", "GET")
      ep.details.technology = "ios"
      helper.ios_origin?(ep).should be_true
    end

    it "returns false for technology 'android'" do
      ep = Endpoint.new("", "GET")
      ep.details.technology = "android"
      helper.ios_origin?(ep).should be_false
    end

    it "handles well_known_applinks with apple-app-site-association file" do
      ep = Endpoint.new("", "GET")
      ep.details.technology = "well_known_applinks"
      ep.details.code_paths << PathInfo.new("path/to/apple-app-site-association")
      helper.ios_origin?(ep).should be_true
    end

    it "returns false for well_known_applinks with assetlinks.json" do
      ep = Endpoint.new("", "GET")
      ep.details.technology = "well_known_applinks"
      ep.details.code_paths << PathInfo.new("path/to/assetlinks.json")
      helper.ios_origin?(ep).should be_false
    end
  end

  describe "#launchable?" do
    it "returns true for scheme urls" do
      helper.launchable?("myapp://path").should be_true
      helper.launchable?("https://example.com").should be_true
    end

    it "returns false for relative path urls starting with /" do
      helper.launchable?("/path/to/something").should be_false
    end
  end

  describe "#shell_quote" do
    it "quotes string for host shell" do
      helper.shell_quote("hello").should eq("'hello'")
      helper.shell_quote("hello'world").should eq("'hello'\\''world'")
    end
  end

  describe "#device_shell_quote" do
    it "quotes once if no device shell metacharacters" do
      helper.device_shell_quote("hello").should eq("'hello'")
    end

    it "quotes twice if metacharacters are present" do
      helper.device_shell_quote("hello&world").should eq("''\\''hello&world'\\'''")
    end
  end

  describe "#plural" do
    it "returns empty string for 1 and 's' for others" do
      helper.plural(1).should eq("")
      helper.plural(0).should eq("s")
      helper.plural(2).should eq("s")
    end
  end
end
