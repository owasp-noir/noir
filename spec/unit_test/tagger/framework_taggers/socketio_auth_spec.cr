require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "SocketIOAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/javascript/socketio_delegated", __DIR__)

  tag = ->(file : String, line : Int32) do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)
    details = Details.new(PathInfo.new("#{fixture_base}/#{file}", line))
    details.technology = "js_socketio"
    endpoint = Endpoint.new("ws://x", "SEND", [] of Param, details)
    endpoint.protocol = "ws"
    SocketIOAuthTagger.new(noir_options).perform([endpoint])
    endpoint.tags
  end

  before_each do
    CodeLocator.instance.clear_all
  end

  it "tags an event whose handler first calls an imported check that throws without a session" do
    tags = tag.call("handlers/chat.js", 9)
    tags.map(&.name).should eq(["auth"])
    tags[0].description.should contain("checkLogin(socket)")
  end

  it "follows a check that hands the socket on to the real one" do
    tag.call("handlers/chat.js", 18).map(&.name).should eq(["auth"])
  end

  it "leaves a check in a catch block, under a condition, or of the wrong polarity untagged" do
    tag.call("handlers/chat.js", 26).should be_empty
    tag.call("handlers/admin.ts", 5).should be_empty
    tag.call("handlers/admin.ts", 12).should be_empty
  end

  it "leaves an event with no check untagged" do
    tag.call("server.ts", 9).should be_empty
  end
end
