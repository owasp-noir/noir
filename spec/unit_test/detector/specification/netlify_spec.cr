require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Netlify routing files" do
  options = create_test_options
  instance = Detector::Specification::Netlify.new options

  it "detects _redirects file and registers its path" do
    locator = CodeLocator.instance
    locator.clear "netlify-redirects"

    instance.detect("site/_redirects", "/old /new 301").should be_true
    locator.all("netlify-redirects").should eq ["site/_redirects"]
  end

  it "detects netlify.toml file and registers its path" do
    locator = CodeLocator.instance
    locator.clear "netlify-toml"

    instance.detect("site/netlify.toml", "[[redirects]]").should be_true
    locator.all("netlify-toml").should eq ["site/netlify.toml"]
  end

  it "ignores unrelated filenames" do
    instance.detect("site/routes.toml", "[[redirects]]").should be_false
  end
end
