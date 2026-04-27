require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/taggers/mcp.cr"
require "yaml"

def default_tagger_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

describe "McpTagger" do
  describe "initialization" do
    it "creates tagger with name" do
      tagger = McpTagger.new(default_tagger_options)
      tagger.should_not be_nil
    end
  end

  describe "perform" do
    it "tags Streamable HTTP MCP endpoint" do
      tagger = McpTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/mcp", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("mcp")
      endpoint.tags[0].tagger.should eq("MCP")
    end

    it "tags nested MCP endpoint path segments" do
      tagger = McpTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/mcp/tools", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("mcp")
    end

    it "tags model-context-protocol paths" do
      tagger = McpTagger.new(default_tagger_options)

      endpoint = Endpoint.new("https://example.com/model-context-protocol", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("mcp")
    end

    it "tags legacy SSE transport pairs" do
      tagger = McpTagger.new(default_tagger_options)

      sse_endpoint = Endpoint.new("/api/sse", "GET")
      message_endpoint = Endpoint.new("/api/messages", "POST")

      tagger.perform([sse_endpoint, message_endpoint])

      sse_endpoint.tags.size.should eq(1)
      sse_endpoint.tags[0].name.should eq("mcp")
      message_endpoint.tags.size.should eq(1)
      message_endpoint.tags[0].name.should eq("mcp")
    end

    it "does not tag standalone SSE endpoint" do
      tagger = McpTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/events/sse", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag MCP management URLs without an MCP path segment" do
      tagger = McpTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/mcp-servers", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end
  end
end
