require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Cloudflare wrangler config" do
  options = create_test_options
  instance = Detector::Specification::CloudflareWrangler.new options

  it "detects wrangler.toml with compatibility_date" do
    src = "name = \"api\"\ncompatibility_date = \"2024-01-01\"\n"
    locator = CodeLocator.instance
    locator.clear "cloudflare-wrangler-spec"

    instance.detect("wrangler.toml", src).should be_true
    locator.all("cloudflare-wrangler-spec").should eq ["wrangler.toml"]
  end

  it "detects wrangler.toml with [[routes]]" do
    src = "name = \"api\"\n[[routes]]\npattern = \"api.example.com/*\"\nzone_name = \"example.com\"\n"
    instance.detect("wrangler.toml", src).should be_true
  end

  it "detects wrangler.jsonc with routes" do
    src = %({"name":"api","routes":[{"pattern":"api.example.com/*"}]})
    instance.detect("wrangler.jsonc", src).should be_true
  end

  it "ignores unrelated filenames" do
    instance.detect("Cargo.toml", "compatibility_date = \"2024-01-01\"").should be_false
  end
end
