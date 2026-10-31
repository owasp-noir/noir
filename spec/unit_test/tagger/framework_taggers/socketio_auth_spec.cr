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
    tags[0].path.should eq("#{fixture_base}/auth.js")
    tags[0].line.should eq(1)
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
    tag.call("server.ts", 10).should be_empty
  end

  it "leaves a check after a write, after a branch that answers, or under an unbraced if untagged" do
    tag.call("edge.js", 21).should be_empty
    tag.call("edge.js", 26).should be_empty
    tag.call("edge.js", 33).should be_empty
    tag.call("edge.js", 57).should be_empty
  end

  it "leaves a nested check, and a check of a non-session property, untagged" do
    tag.call("edge.js", 38).should be_empty
    tag.call("edge.js", 46).should be_empty
  end

  it "notes a setting early return before the check" do
    tags = tag.call("edge.js", 42)
    tags.map(&.name).should eq(["auth"])
    tags[0].description.should end_with("— a setting can lift it")
  end

  it "lets a log line, an awaited read and a wrapped declaration come before the check" do
    tag.call("lead.js", 29).map(&.name).should eq(["auth"])
    tag.call("lead.js", 34).map(&.name).should eq(["auth"])
    tag.call("lead.js", 44).map(&.name).should eq(["auth"])
  end

  it "leaves an awaited write, or a shuffle whose condition calls something, before the check untagged" do
    tag.call("lead.js", 39).should be_empty
    tag.call("lead.js", 51).should be_empty
  end

  it "reads a check that logs first, rethrows from a try, or tests `logged`" do
    tag.call("lead.js", 57).map(&.name).should eq(["auth"])
    tag.call("lead.js", 61).map(&.name).should eq(["auth"])
    tag.call("lead.js", 65).map(&.name).should eq(["auth"])
  end

  it "reads a file that uses net without serving it" do
    tag.call("lead.js", 69).map(&.name).should eq(["auth"])
  end

  it "reads function callbacks, one-line try blocks and argument shuffles" do
    tag.call("edge.js", 50).map(&.name).should eq(["auth"])
    tag.call("edge.js", 54).map(&.name).should eq(["auth"])
    tag.call("edge.js", 60).map(&.name).should eq(["auth"])
  end
end
