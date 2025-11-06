require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/taggers/oauth.cr"
require "yaml"

def default_tagger_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

describe "OAuthTagger" do
  describe "initialization" do
    it "creates tagger with name" do
      tagger = OAuthTagger.new(default_tagger_options)
      tagger.should_not be_nil
    end
  end

  describe "perform" do
    it "tags endpoint with OAuth parameters" do
      tagger = OAuthTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/oauth/token", "POST", [
        Param.new("grant_type", "authorization_code", "form"),
        Param.new("code", "abc123", "form"),
        Param.new("client_id", "my-app", "form"),
        Param.new("redirect_uri", "https://example.com/callback", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("oauth")
    end

    it "requires at least 3 matching parameters" do
      tagger = OAuthTagger.new(default_tagger_options)

      # Only 2 matching parameters
      endpoint = Endpoint.new("/api/auth", "POST", [
        Param.new("grant_type", "password", "form"),
        Param.new("client_id", "my-app", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "tags with exactly 3 matching parameters" do
      tagger = OAuthTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/oauth/token", "POST", [
        Param.new("grant_type", "client_credentials", "form"),
        Param.new("client_id", "my-app", "form"),
        Param.new("client_secret", "secret", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("oauth")
    end

    it "does not tag endpoint without OAuth parameters" do
      tagger = OAuthTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/data", "GET", [
        Param.new("user_id", "123", "query"),
        Param.new("page", "1", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "handles multiple endpoints" do
      tagger = OAuthTagger.new(default_tagger_options)

      endpoint1 = Endpoint.new("/oauth/token", "POST", [
        Param.new("grant_type", "authorization_code", "form"),
        Param.new("code", "abc123", "form"),
        Param.new("client_id", "my-app", "form"),
      ])

      endpoint2 = Endpoint.new("/api/users", "GET", [
        Param.new("name", "John", "query"),
      ])

      tagger.perform([endpoint1, endpoint2])

      endpoint1.tags.size.should eq(1)
      endpoint2.tags.size.should eq(0)
    end

    it "is case-sensitive for parameter matching" do
      tagger = OAuthTagger.new(default_tagger_options)

      # OAuth parameter names are case-sensitive
      endpoint = Endpoint.new("/oauth/token", "POST", [
        Param.new("GRANT_TYPE", "authorization_code", "form"),
        Param.new("CODE", "abc123", "form"),
        Param.new("CLIENT_ID", "my-app", "form"),
      ])

      tagger.perform([endpoint])

      # Should not match because case doesn't match
      endpoint.tags.size.should eq(0)
    end
  end
end
