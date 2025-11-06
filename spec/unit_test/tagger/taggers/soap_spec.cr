require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/taggers/soap.cr"
require "yaml"

def default_tagger_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

describe "SoapTagger" do
  describe "initialization" do
    it "creates tagger with name" do
      tagger = SoapTagger.new(default_tagger_options)
      tagger.should_not be_nil
    end
  end

  describe "perform" do
    it "tags endpoint with SOAPAction header" do
      tagger = SoapTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/webservice", "POST", [
        Param.new("SOAPAction", "http://example.com/GetUser", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("soap")
    end

    it "is case-insensitive for header matching" do
      tagger = SoapTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/webservice", "POST", [
        Param.new("soapaction", "http://example.com/GetUser", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("soap")
    end

    it "does not tag endpoint without SOAP parameters" do
      tagger = SoapTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/data", "POST", [
        Param.new("user_id", "123", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "handles multiple endpoints" do
      tagger = SoapTagger.new(default_tagger_options)

      endpoint1 = Endpoint.new("/soap", "POST", [
        Param.new("soapaction", "GetData", "header"),
      ])

      endpoint2 = Endpoint.new("/rest", "POST", [
        Param.new("action", "getData", "json"),
      ])

      tagger.perform([endpoint1, endpoint2])

      endpoint1.tags.size.should eq(1)
      endpoint2.tags.size.should eq(0)
    end
  end
end
