require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/taggers/pii.cr"
require "yaml"

def default_tagger_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

describe "PiiTagger" do
  describe "initialization" do
    it "creates tagger with name" do
      tagger = PiiTagger.new(default_tagger_options)
      tagger.name.should eq("pii")
    end
  end

  describe "perform" do
    it "tags an endpoint with a single strong PII parameter" do
      tagger = PiiTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/kyc", "POST", [
        Param.new("ssn", "", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("pii")
    end

    it "tags an endpoint carrying credit card data" do
      tagger = PiiTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/billing", "POST", [
        Param.new("card_number", "", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("pii")
    end

    it "tags an endpoint with two or more medium PII parameters" do
      tagger = PiiTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/profile", "POST", [
        Param.new("email", "", "json"),
        Param.new("phone", "", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("pii")
    end

    it "does not tag an endpoint with a single medium PII parameter" do
      tagger = PiiTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/newsletter", "POST", [
        Param.new("email", "", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag an endpoint without PII parameters" do
      tagger = PiiTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/ping", "GET", [
        Param.new("q", "", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "is case-insensitive and normalizes separators" do
      tagger = PiiTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/v", "POST", [
        Param.new("Credit-Card", "", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("pii")
    end

    it "normalizes camelCase strong names (dateOfBirth)" do
      tagger = PiiTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/kyc", "POST", [
        Param.new("dateOfBirth", "", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("pii")
    end

    it "tags two camelCase medium names (firstName + lastName)" do
      tagger = PiiTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/profile", "POST", [
        Param.new("firstName", "", "json"),
        Param.new("lastName", "", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("pii")
    end

    it "matches a strong token inside a compound name (customerSsn)" do
      tagger = PiiTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/customer", "POST", [
        Param.new("customerSsn", "", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("pii")
    end

    it "does not tag a benign token that merely contains a PII substring" do
      tagger = PiiTagger.new(default_tagger_options)

      # `lesson` contains the substring "ssn" but is a single token, so
      # token matching must not fire on it.
      endpoint = Endpoint.new("/api/courses", "POST", [
        Param.new("lessonId", "", "json"),
        Param.new("lessonName", "", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end
  end
end
