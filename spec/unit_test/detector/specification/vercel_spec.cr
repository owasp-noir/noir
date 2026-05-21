require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Vercel config" do
  options = create_test_options
  instance = Detector::Specification::Vercel.new options

  it "detects vercel.json" do
    content = <<-JSON
      {
        "rewrites": [{"source":"/api/(.*)", "destination":"/api/$1"}]
      }
      JSON

    instance.detect("vercel.json", content).should be_true
  end

  it "detects legacy now.json" do
    content = <<-JSON
      {
        "routes": [{"src":"^/api/(.*)", "dest":"/api/$1"}]
      }
      JSON

    instance.detect("now.json", content).should be_true
  end

  it "rejects non-config files" do
    instance.detect("config.json", %({"rewrites": []})).should be_false
  end

  it "accepts only root-level config names" do
    instance.detect("apps/web/vercel.json", %({"rewrites": []})).should be_false
  end

  it "registers path in code_locator" do
    locator = CodeLocator.instance
    locator.clear "vercel-spec"

    instance.detect("vercel.json", %({"redirects":[{"source":"/old","destination":"/new"}]}))
    locator.all("vercel-spec").should eq(["vercel.json"])
  end
end
