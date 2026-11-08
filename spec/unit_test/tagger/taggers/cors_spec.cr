require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/tagger.cr"
require "yaml"

def default_tagger_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

describe "cors rule (src/tagger/rules/cors.yml)" do
  describe "initialization" do
    it "creates tagger with name" do
      tagger = NoirTaggers.build("cors", default_tagger_options).not_nil!
      tagger.should_not be_nil
    end
  end

  describe "perform" do
    it "tags endpoint with CORS parameter" do
      tagger = NoirTaggers.build("cors", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/data", "GET", [
        Param.new("origin", "https://example.com", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("cors")
    end

    it "tags endpoint with access-control-allow-origin" do
      tagger = NoirTaggers.build("cors", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/data", "GET", [
        Param.new("access-control-allow-origin", "*", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("cors")
    end

    it "tags endpoint with access-control-allow-credentials" do
      tagger = NoirTaggers.build("cors", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/data", "OPTIONS", [
        Param.new("access-control-allow-credentials", "true", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("cors")
    end

    it "tags endpoint with access-control-request-headers" do
      tagger = NoirTaggers.build("cors", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/data", "OPTIONS", [
        Param.new("Access-Control-Request-Headers", "X-Custom", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("cors")
    end

    it "tags a CGI-style HTTP_ORIGIN header" do
      tagger = NoirTaggers.build("cors", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/data", "GET", [
        Param.new("HTTP_ORIGIN", "https://example.com", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("cors")
    end

    it "does not tag endpoint without CORS parameters" do
      tagger = NoirTaggers.build("cors", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/data", "GET", [
        Param.new("user_id", "123", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "handles multiple endpoints" do
      tagger = NoirTaggers.build("cors", default_tagger_options).not_nil!

      endpoint1 = Endpoint.new("/api/data", "GET", [
        Param.new("origin", "https://example.com", "header"),
      ])

      endpoint2 = Endpoint.new("/api/users", "POST", [
        Param.new("name", "John", "json"),
      ])

      tagger.perform([endpoint1, endpoint2])

      endpoint1.tags.size.should eq(1)
      endpoint2.tags.size.should eq(0)
    end

    it "is case-insensitive for parameter matching" do
      tagger = NoirTaggers.build("cors", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/data", "GET", [
        Param.new("Origin", "https://example.com", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
    end

    it "does not tag a non-header param named origin (e.g. a query param)" do
      tagger = NoirTaggers.build("cors", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/flights", "GET", [
        Param.new("origin", "JFK", "query"),
        Param.new("destination", "LAX", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end
  end
end
