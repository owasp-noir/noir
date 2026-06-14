require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/taggers/webhook.cr"
require "yaml"

def default_tagger_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

describe "WebhookTagger" do
  describe "initialization" do
    it "creates tagger with name" do
      tagger = WebhookTagger.new(default_tagger_options)
      tagger.name.should eq("webhook")
    end
  end

  describe "perform" do
    it "tags an endpoint under a /webhook path regardless of method" do
      tagger = WebhookTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/webhooks/stripe", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("webhook")
    end

    it "tags an endpoint with a provider signature header" do
      tagger = WebhookTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/integrations/github", "POST", [
        Param.new("X-Hub-Signature-256", "", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("webhook")
    end

    it "tags a POST /callback endpoint" do
      tagger = WebhookTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/payments/callback", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("webhook")
    end

    it "tags a wildcard/any-method /callback route" do
      tagger = WebhookTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/payments/callback", "ANY")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("webhook")
    end

    it "does not tag a GET /callback endpoint without other signals" do
      tagger = WebhookTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/auth/callback", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag an OAuth/OIDC authorization-code callback (FP guard)" do
      ["/api/oauth/callback", "/oauth2/callback", "/openid/callback",
       "/auth/google/callback", "/auth/:provider/callback",
       "/users/auth/github/callback"].each do |path|
        tagger = WebhookTagger.new(default_tagger_options)
        endpoint = Endpoint.new(path, "POST", [
          Param.new("code", "", "query"),
          Param.new("state", "", "query"),
        ])

        tagger.perform([endpoint])

        endpoint.tags.size.should eq(0)
      end
    end

    it "still tags a webhook under an auth path via a strong signal" do
      tagger = WebhookTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/auth/webhooks/provider", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("webhook")
    end

    it "does not tag an unrelated endpoint" do
      tagger = WebhookTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/users", "POST", [
        Param.new("name", "", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "tags on newer provider signature headers" do
      ["X-Shopify-Hmac-Sha256", "Svix-Signature", "X-Razorpay-Signature",
       "X-Line-Signature", "X-Amz-Sns-Message-Type"].each do |header|
        tagger = WebhookTagger.new(default_tagger_options)
        endpoint = Endpoint.new("/integrations/x", "POST", [
          Param.new(header, "", "header"),
        ])

        tagger.perform([endpoint])

        endpoint.tags.size.should eq(1)
        endpoint.tags[0].name.should eq("webhook")
      end
    end

    it "does not tag an in-app notifications resource (FP guard)" do
      ["POST", "DELETE", "PUT"].each do |method|
        tagger = WebhookTagger.new(default_tagger_options)
        endpoint = Endpoint.new("/api/notifications", method)

        tagger.perform([endpoint])

        endpoint.tags.size.should eq(0)
      end
    end

    it "still tags a POST /notify (payment IPN callback)" do
      tagger = WebhookTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/payment/notify", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("webhook")
    end
  end
end
