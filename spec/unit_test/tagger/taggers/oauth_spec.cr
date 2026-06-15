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

      endpoint = Endpoint.new("/api/integrations/token", "POST", [
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

    it "normalizes parameter names for matching" do
      tagger = OAuthTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/oauth/token", "POST", [
        Param.new("GRANT_TYPE", "authorization_code", "form"),
        Param.new("CODE", "abc123", "form"),
        Param.new("CLIENT_ID", "my-app", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("oauth")
    end

    it "tags OAuth authorization endpoints with OIDC parameters" do
      tagger = OAuthTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/oauth2/authorize", "GET", [
        Param.new("response_type", "code", "query"),
        Param.new("client_id", "my-app", "query"),
        Param.new("redirect_uri", "https://example.com/callback", "query"),
        Param.new("scope", "openid profile", "query"),
        Param.new("state", "abc123", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("oauth")
    end

    it "tags OAuth token endpoints using PKCE verifier without client secret" do
      tagger = OAuthTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/oauth/token", "POST", [
        Param.new("grant-type", "authorization_code", "form"),
        Param.new("code_verifier", "pkce-secret", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("oauth")
    end

    it "does not tag generic token routes with weak OAuth parameters" do
      tagger = OAuthTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/token", "POST", [
        Param.new("code", "123456", "form"),
        Param.new("state", "ready", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag non-OAuth endpoints with weak OAuth-like parameter names" do
      tagger = OAuthTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/promotions", "POST", [
        Param.new("code", "SPRING", "form"),
        Param.new("state", "published", "form"),
        Param.new("scope", "regional", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "tags the authorization-code redirect handler on a callback path" do
      tagger = OAuthTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/users/auth/google/callback", "GET", [
        Param.new("code", "abc123", "query"),
        Param.new("state", "xyz", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("oauth")
    end

    it "tags an /oauth path carrying a single OAuth parameter" do
      tagger = OAuthTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/oauth/authorize", "GET", [
        Param.new("client_id", "my-app", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("oauth")
    end

    it "tags the OAuth device-flow token endpoint" do
      tagger = OAuthTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/oauth/token", "POST", [
        Param.new("grant_type", "urn:ietf:params:oauth:grant-type:device_code", "form"),
        Param.new("device_code", "GmRh...", "form"),
        Param.new("client_id", "my-app", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("oauth")
    end

    it "tags param-less endpoints under a strong /oauth2 path segment" do
      ["/oauth2/auth", "/oauth2/device/auth", "/oauth2/device/verify",
       "/oauth2/sessions/logout", "/oauth/authorize",
       "/openid/userinfo", "/oidc/token"].each do |path|
        tagger = OAuthTagger.new(default_tagger_options)
        endpoint = Endpoint.new(path, "GET")

        tagger.perform([endpoint])

        endpoint.tags.size.should eq(1)
        endpoint.tags[0].name.should eq("oauth")
      end
    end

    it "does not tag a path that merely contains 'openid' as a sub-token" do
      tagger = OAuthTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/.well-known/openid-configuration", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag a generic callback receiving only a code" do
      tagger = OAuthTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/payment/callback", "GET", [
        Param.new("code", "settled", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag a bearer-protected resource served from an oauth host" do
      tagger = OAuthTagger.new(default_tagger_options)

      endpoint = Endpoint.new("https://oauth.example.com/api/users", "GET", [
        Param.new("access_token", "ya29...", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag an OIDC discovery document with no OAuth parameters" do
      tagger = OAuthTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/.well-known/openid-configuration", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "tags a param-less social-login callback under an auth context" do
      tagger = OAuthTagger.new(default_tagger_options)

      # Laravel Socialite style (e.g. koel): the `code`/`state` params
      # arrive at runtime and aren't statically extracted, but
      # `/auth/<provider>/callback` is unambiguously an OAuth flow.
      endpoint = Endpoint.new("/auth/google/callback", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("oauth")
    end

    it "tags a param-less social-login redirect under an auth context" do
      tagger = OAuthTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/auth/google/redirect", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("oauth")
    end

    it "tags an SSO callback handler with no extracted params" do
      tagger = OAuthTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/sso/callback", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("oauth")
    end

    it "does not tag a callback without an auth/SSO context segment" do
      tagger = OAuthTagger.new(default_tagger_options)

      # No auth/SSO context word in the path and no OAuth params — this is
      # a payment IPN, not an OAuth sign-in flow.
      endpoint = Endpoint.new("/payments/stripe/callback", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end
  end
end
