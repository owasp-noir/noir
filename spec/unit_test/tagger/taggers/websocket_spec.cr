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

    it "tags endpoints with wss / websocket protocol (AsyncAPI), case-insensitively" do
      ["wss", "websocket", "WS", "WSS"].each do |proto|
        tagger = WebsocketTagger.new(default_tagger_options)
        endpoint = Endpoint.new("/chat", "GET")
        endpoint.protocol = proto

        tagger.perform([endpoint])

        endpoint.tags.size.should eq(1)
        endpoint.tags[0].name.should eq("websocket")
      end
    end

    it "does not tag non-websocket protocols (http, kafka, mqtt)" do
      ["http", "kafka", "mqtt"].each do |proto|
        tagger = WebsocketTagger.new(default_tagger_options)
        endpoint = Endpoint.new("/topic", "GET")
        endpoint.protocol = proto

        tagger.perform([endpoint])

        endpoint.tags.size.should eq(0)
      end
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

    it "tags on a single conclusive handshake header (Sec-WebSocket-Key)" do
      tagger = WebsocketTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/chat", "GET", [
        Param.new("sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ==", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("websocket")
    end

    it "tags on Sec-WebSocket-Accept alone" do
      tagger = WebsocketTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/chat", "GET", [
        Param.new("Sec-WebSocket-Accept", "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
    end

    it "requires at least 2 weak handshake headers" do
      tagger = WebsocketTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/chat", "GET", [
        Param.new("sec-websocket-version", "13", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "tags on two weak handshake headers" do
      tagger = WebsocketTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/chat", "GET", [
        Param.new("sec-websocket-version", "13", "header"),
        Param.new("sec-websocket-protocol", "chat", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
    end

    it "tags on an explicit Upgrade: websocket header" do
      tagger = WebsocketTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/chat", "GET", [
        Param.new("Upgrade", "websocket", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
    end

    it "tags Socket.IO / SockJS URLs even when protocol stays http" do
      ["/socket.io/", "/sockjs/info"].each do |path|
        tagger = WebsocketTagger.new(default_tagger_options)
        endpoint = Endpoint.new(path, "GET")
        endpoint.protocol = "http"

        tagger.perform([endpoint])

        endpoint.tags.size.should eq(1)
        endpoint.tags[0].name.should eq("websocket")
      end
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
