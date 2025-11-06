require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/taggers/websocket.cr"
require "yaml"

def default_tagger_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

describe "WebsocketTagger" do
  describe "initialization" do
    it "creates tagger with name" do
      tagger = WebsocketTagger.new(default_tagger_options)
      tagger.should_not be_nil
    end
  end

  describe "perform" do
    it "tags endpoint with ws protocol" do
      tagger = WebsocketTagger.new(default_tagger_options)

      endpoint = Endpoint.new("ws://example.com/chat", "GET")
      endpoint.protocol = "ws"

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("websocket")
    end

    it "tags endpoint with WebSocket headers" do
      tagger = WebsocketTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/chat", "GET", [
        Param.new("sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ==", "header"),
        Param.new("sec-websocket-version", "13", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("websocket")
    end

    it "requires at least 2 matching headers" do
      tagger = WebsocketTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/chat", "GET", [
        Param.new("sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ==", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag endpoint without WebSocket indicators" do
      tagger = WebsocketTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/data", "GET", [
        Param.new("user_id", "123", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "is case-insensitive for header matching" do
      tagger = WebsocketTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/chat", "GET", [
        Param.new("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==", "header"),
        Param.new("Sec-WebSocket-Version", "13", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
    end
  end
end
