require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/taggers/payment.cr"
require "yaml"

def default_tagger_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

describe "PaymentTagger" do
  describe "initialization" do
    it "creates tagger with name" do
      tagger = PaymentTagger.new(default_tagger_options)
      tagger.name.should eq("payment")
    end
  end

  describe "perform" do
    it "tags an endpoint under a /checkout path" do
      tagger = PaymentTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/checkout", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("payment")
    end

    it "tags an endpoint with card data parameters" do
      tagger = PaymentTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/orders", "POST", [
        Param.new("card_number", "", "json"),
        Param.new("cvv", "", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("payment")
    end

    it "tags an endpoint with an amount + currency pair" do
      tagger = PaymentTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/transfer", "POST", [
        Param.new("amount", "100", "json"),
        Param.new("currency", "USD", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("payment")
    end

    it "tags an ambiguous /transactions path when a money parameter corroborates" do
      tagger = PaymentTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/transactions", "GET", [
        Param.new("amount", "10", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("payment")
    end

    it "does not tag an ambiguous /subscriptions path without a money parameter" do
      tagger = PaymentTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/subscriptions", "POST", [
        Param.new("endpoint", "https://push.example/abc", "json"),
        Param.new("keys", "", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag on amount alone" do
      tagger = PaymentTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/survey", "POST", [
        Param.new("amount", "5", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag an unrelated endpoint" do
      tagger = PaymentTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/articles", "GET", [
        Param.new("page", "1", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "tags a /pay path" do
      tagger = PaymentTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/pay", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("payment")
    end

    it "tags a /purchase path" do
      tagger = PaymentTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/purchase", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("payment")
    end

    it "tags an endpoint carrying bank-transfer details (IBAN)" do
      tagger = PaymentTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/beneficiaries", "POST", [
        Param.new("iban", "DE89...", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("payment")
    end

    it "tags an ambiguous /orders path when a money parameter corroborates" do
      tagger = PaymentTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/orders", "POST", [
        Param.new("total", "42", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("payment")
    end

    it "tags a wallet withdrawal carrying an amount" do
      tagger = PaymentTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/wallet/withdraw", "POST", [
        Param.new("amount", "100", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("payment")
    end

    it "does not tag a non-financial withdraw without a money parameter" do
      tagger = PaymentTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/applications/123/withdraw", "POST", [
        Param.new("reason", "changed my mind", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end
  end
end
