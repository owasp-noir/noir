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

    it "tags bearer authorization values without a second token parameter" do
      tagger = JwtTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/profile", "GET", [
        Param.new("Authorization", "Bearer eyJhbGciOiJIUzI1NiJ9.payload.signature", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("jwt")
    end

    it "tags auth routes with custom token header names" do
      tagger = JwtTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/login", "POST", [
        Param.new("x-api-token", "", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("jwt")
    end

    it "does not tag CSRF-only token parameters" do
      tagger = JwtTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/auth/session", "POST", [
        Param.new("csrf_token", "", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag Devise-style reset/confirmation tokens on auth routes" do
      tagger = JwtTagger.new(default_tagger_options)

      reset = Endpoint.new("/auth/password/edit", "GET", [
        Param.new("reset_password_token", "abc123", "query"),
      ])
      confirm = Endpoint.new("/auth/confirmation", "GET", [
        Param.new("confirmation_token", "abc123", "query"),
      ])
      unlock = Endpoint.new("/auth/unlock", "GET", [
        Param.new("unlock_token", "abc123", "query"),
      ])

      tagger.perform([reset, confirm, unlock])

      reset.tags.size.should eq(0)
      confirm.tags.size.should eq(0)
      unlock.tags.size.should eq(0)
    end

    it "does not tag API pagination tokens" do
      tagger = JwtTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/items", "GET", [
        Param.new("page_token", "CAEaBg", "query"),
        Param.new("next_token", "CAEaBg", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag a Basic auth Authorization header as JWT" do
      tagger = JwtTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/login", "POST", [
        Param.new("Authorization", "Basic dXNlcjpwYXNz", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "still tags an empty Authorization header on an auth route" do
      tagger = JwtTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/login", "POST", [
        Param.new("Authorization", "", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.map(&.name).should contain("jwt")
    end
  end
end
