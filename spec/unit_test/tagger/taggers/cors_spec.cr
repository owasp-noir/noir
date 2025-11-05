require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/taggers/cors.cr"
require "yaml"

def default_tagger_options
  {
    "debug" => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color" => YAML::Any.new(false),
    "nolog" => YAML::Any.new(false)
  }
end

describe "CorsTagger" do
  describe "initialization" do
    it "creates tagger with name" do
      tagger = CorsTagger.new(default_tagger_options)
      tagger.should_not be_nil
    end
  end

  describe "perform" do
    it "tags endpoint with CORS parameter" do
      tagger = CorsTagger.new(default_tagger_options)
      
      endpoint = Endpoint.new("/api/data", "GET", [
        Param.new("origin", "https://example.com", "header")
      ])
      
      tagger.perform([endpoint])
      
      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("cors")
    end

    it "tags endpoint with access-control-allow-origin" do
      tagger = CorsTagger.new(default_tagger_options)
      
      endpoint = Endpoint.new("/api/data", "GET", [
        Param.new("access-control-allow-origin", "*", "header")
      ])
      
      tagger.perform([endpoint])
      
      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("cors")
    end

    it "does not tag endpoint without CORS parameters" do
      tagger = CorsTagger.new(default_tagger_options)
      
      endpoint = Endpoint.new("/api/data", "GET", [
        Param.new("user_id", "123", "query")
      ])
      
      tagger.perform([endpoint])
      
      endpoint.tags.size.should eq(0)
    end

    it "handles multiple endpoints" do
      tagger = CorsTagger.new(default_tagger_options)
      
      endpoint1 = Endpoint.new("/api/data", "GET", [
        Param.new("origin", "https://example.com", "header")
      ])
      
      endpoint2 = Endpoint.new("/api/users", "POST", [
        Param.new("name", "John", "json")
      ])
      
      tagger.perform([endpoint1, endpoint2])
      
      endpoint1.tags.size.should eq(1)
      endpoint2.tags.size.should eq(0)
    end

    it "is case-insensitive for parameter matching" do
      tagger = CorsTagger.new(default_tagger_options)
      
      endpoint = Endpoint.new("/api/data", "GET", [
        Param.new("Origin", "https://example.com", "header")
      ])
      
      tagger.perform([endpoint])
      
      endpoint.tags.size.should eq(1)
    end
  end
end
