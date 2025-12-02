require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/taggers/jwt.cr"
require "yaml"

def default_tagger_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

describe "JwtTagger" do
  describe "initialization" do
    it "creates tagger with name" do
      tagger = JwtTagger.new(default_tagger_options)
      tagger.should_not be_nil
    end
  end

  describe "perform" do
    it "tags endpoint with token and refresh_token parameters" do
      tagger = JwtTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/login", "POST", [
        Param.new("token", "", "form"),
        Param.new("refresh_token", "", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("jwt")
    end

    it "tags endpoint with JWT URL path and token parameter" do
      tagger = JwtTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/auth/token", "POST", [
        Param.new("token", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("jwt")
    end

    it "tags endpoint with /refresh URL path" do
      tagger = JwtTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/refresh", "POST", [
        Param.new("refresh_token", "", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("jwt")
    end

    it "does not tag endpoint without JWT parameters" do
      tagger = JwtTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/users", "GET", [
        Param.new("user_id", "123", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "tags endpoint with access_token and id_token parameters" do
      tagger = JwtTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/verify", "POST", [
        Param.new("access_token", "", "form"),
        Param.new("id_token", "", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("jwt")
    end

    it "handles multiple endpoints" do
      tagger = JwtTagger.new(default_tagger_options)

      endpoint1 = Endpoint.new("/auth/token", "POST", [
        Param.new("token", "", "form"),
      ])

      endpoint2 = Endpoint.new("/api/users", "GET", [
        Param.new("name", "John", "query"),
      ])

      tagger.perform([endpoint1, endpoint2])

      endpoint1.tags.size.should eq(1)
      endpoint2.tags.size.should eq(0)
    end

    it "is case-insensitive for parameter matching" do
      tagger = JwtTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/auth", "POST", [
        Param.new("Token", "", "form"),
        Param.new("JWT", "", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
    end

    it "tags endpoint with authorization header" do
      tagger = JwtTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/auth", "POST", [
        Param.new("authorization", "Bearer token", "header"),
        Param.new("token", "", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("jwt")
    end
  end
end
