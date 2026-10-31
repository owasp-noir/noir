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

  it "tags a 403 for a key that is in none of the accepted env secrets" do
    tags = tag.call("app/api/cron-key/route.ts", 3)
    tags.map(&.name).should eq(["auth"])
    tags[0].description.should contain("replies 403")
  end

  it "leaves a refusal of the caller who has the key untagged" do
    tag.call("app/api/cron-key/route.ts", 11).should be_empty
  end

  it "tags a handler whose first statements call a same-file helper that throws 401" do
    tags = tag.call("app/api/helper/route.ts", 13)
    tags.map(&.name).should eq(["auth"])
    tags[0].description.should contain("authMiddleware()")
  end

  it "tags a handler calling an imported helper that refuses a wrong cron key" do
    tag.call("app/api/helper/route.ts", 25).map(&.name).should eq(["auth"])
  end

  it "leaves a helper called under a branch, or one refusing a signed-in caller, untagged" do
    tag.call("app/api/helper/route.ts", 18).should be_empty
    tag.call("app/api/helper/route.ts", 30).should be_empty
  end

  it "leaves a check after a write, and a dropped returned 401, untagged" do
    tag.call("app/api/order/route.ts", 5).should be_empty
    tag.call("app/api/order/route.ts", 12).should be_empty
  end

  it "tags a returned 401 the handler hands on" do
    tag.call("app/api/order/route.ts", 19).map(&.name).should eq(["auth"])
  end

  it "leaves a list with a public value, and a NEXT_PUBLIC_ key, untagged" do
    tag.call("app/api/order/route.ts", 26).should be_empty
    tag.call("app/api/order/route.ts", 35).should be_empty
  end

  it "lets an awaited read and a log line come before the helper, not an awaited write" do
    tag.call("app/api/lead/route.ts", 7).map(&.name).should eq(["auth"])
    tag.call("app/api/lead/route.ts", 15).should be_empty
  end

  it "reads the handler a wrapper is handed, and a secret inside a template literal" do
    tags = tag.call("app/api/lead/route.ts", 22)
    tags.map(&.name).should eq(["auth"])
    tags[0].description.should contain("cronHandler")
    tag.call("lib/cron.ts", 11).map(&.name).should eq(["auth"])
  end

  it "leaves a template holding a public value untagged" do
    tag.call("lib/cron.ts", 16).should be_empty
  end

  it "tags a handler that returns the helper's response" do
    tag.call("app/api/lead/route.ts", 24).map(&.name).should eq(["auth"])
  end

  it "leaves a fetch POST, a tagged-template write or an awaiting log line before the helper untagged" do
    tag.call("app/api/effects/route.ts", 5).should be_empty
    tag.call("app/api/effects/route.ts", 11).should be_empty
    tag.call("app/api/effects/route.ts", 17).should be_empty
  end

  it "leaves a pages-router helper called after a verb branch untagged" do
    tag.call("pages/api/branchy.ts", 11).should be_empty
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
