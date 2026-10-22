require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "NextjsAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/javascript/nextjs_auth", __DIR__)

  tag = ->(file : String, line : Int32) do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)
    details = Details.new(PathInfo.new("#{fixture_base}/#{file}", line))
    details.technology = "js_nextjs"
    endpoint = Endpoint.new("/x", "GET", [] of Param, details)
    NextjsAuthTagger.new(noir_options).perform([endpoint])
    endpoint.tags
  end

  before_each do
    CodeLocator.instance.clear_all
  end

  it "tags an app-router handler that replies 401 without a session" do
    tags = tag.call("app/api/me/route.ts", 4)
    tags.map(&.name).should eq(["auth"])
    tags[0].description.should contain("if (!session?.user)")
  end

  it "tags a handler that compares the caller's key with a process.env secret" do
    tag.call("app/api/cron/route.ts", 3).map(&.name).should eq(["auth"])
  end

  it "tags a pages-router handler that sets res.status(401)" do
    tag.call("pages/api/profile.ts", 4).map(&.name).should eq(["auth"])
  end

  it "leaves a login route's credential failure untagged" do
    tag.call("app/api/login/route.ts", 4).should be_empty
  end

  it "tags a pages-router handler whose only verb branch refuses others with 405" do
    tag.call("pages/api/settings.ts", 4).map(&.name).should eq(["auth"])
  end

  it "reads a Prettier-wrapped 401 reply up to its if" do
    tag.call("app/api/wrapped/route.ts", 4).map(&.name).should eq(["auth"])
  end

  it "leaves a shared pages-router handler untagged when a verb branch returns first" do
    tag.call("pages/api/shared.ts", 4).should be_empty
  end

  it "stops at the handler's own closing brace" do
    tag.call("app/api/public/route.ts", 4).should be_empty
    tag.call("app/api/public/route.ts", 21).map(&.name).should eq(["auth"])
  end

  it "ignores a closed if, a commented condition and a non-secret env comparison above a 401" do
    tag.call("app/api/public/route.ts", 8).should be_empty
  end

  it "reads the resolved handler, not the export line" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)
    path = "#{fixture_base}/app/api/me/route.ts"
    details = Details.new(PathInfo.new(path, 12))
    details.technology = "js_nextjs"
    endpoint = Endpoint.new("/api/me", "GET", [] of Param, details)
    endpoint.handler = Handler.new("getHandler", path, 4)
    NextjsAuthTagger.new(noir_options).perform([endpoint])
    endpoint.tags.map(&.name).should eq(["auth"])
  end
end
