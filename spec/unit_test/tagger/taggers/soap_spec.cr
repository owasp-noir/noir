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

describe "soap rule (src/tagger/rules/soap.yml)" do
  describe "initialization" do
    it "creates tagger with name" do
      tagger = NoirTaggers.build("soap", default_tagger_options).not_nil!
      tagger.should_not be_nil
    end
  end

  describe "perform" do
    it "tags endpoint with SOAPAction header" do
      tagger = NoirTaggers.build("soap", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/webservice", "POST", [
        Param.new("SOAPAction", "http://example.com/GetUser", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("soap")
    end

    it "is case-insensitive for header matching" do
      tagger = NoirTaggers.build("soap", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/webservice", "POST", [
        Param.new("soapaction", "http://example.com/GetUser", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("soap")
    end

    it "does not tag endpoint without SOAP parameters" do
      tagger = NoirTaggers.build("soap", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/data", "POST", [
        Param.new("user_id", "123", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "handles multiple endpoints" do
      tagger = NoirTaggers.build("soap", default_tagger_options).not_nil!

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

    it "tags WSDL / ASMX URLs" do
      ["/service?wsdl", "/Service.wsdl", "/Account.asmx"].each do |url|
        tagger = NoirTaggers.build("soap", default_tagger_options).not_nil!
        endpoint = Endpoint.new(url, "GET")

        tagger.perform([endpoint])

        endpoint.tags.size.should eq(1)
        endpoint.tags[0].name.should eq("soap")
      end
    end

    it "tags a SOAP 1.2 Content-Type header" do
      tagger = NoirTaggers.build("soap", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/webservice", "POST", [
        Param.new("Content-Type", "application/soap+xml; charset=utf-8", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("soap")
    end

    it "does not tag a bare 'soap' path segment (store listing FP)" do
      tagger = NoirTaggers.build("soap", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/products/soap", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "ignores a soapaction-like name on a non-header param" do
      tagger = NoirTaggers.build("soap", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/data", "POST", [
        Param.new("soapaction", "x", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end
  end
end
