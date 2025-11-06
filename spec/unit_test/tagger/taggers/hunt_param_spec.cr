require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/taggers/hunt_param.cr"
require "yaml"

def default_tagger_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

describe "HuntParamTagger" do
  describe "initialization" do
    it "creates tagger with name" do
      tagger = HuntParamTagger.new(default_tagger_options)
      tagger.should_not be_nil
    end
  end

  describe "perform" do
    it "tags SSTI vulnerable parameters" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/render", "GET", [
        Param.new("template", "user_profile", "query"),
      ])

      tagger.perform([endpoint])

      # 'template' matches both ssti and file-inclusion
      endpoint.params[0].tags.size.should be >= 1
      tag_names = endpoint.params[0].tags.map(&.name)
      tag_names.should contain("ssti")
    end

    it "tags SSRF vulnerable parameters" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/fetch", "GET", [
        Param.new("url", "http://example.com", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.size.should eq(1)
      endpoint.params[0].tags[0].name.should eq("ssrf")
    end

    it "tags SQLi vulnerable parameters" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/users", "GET", [
        Param.new("id", "123", "query"),
      ])

      tagger.perform([endpoint])

      # 'id' matches both sqli and idor
      endpoint.params[0].tags.size.should be >= 1
      tag_names = endpoint.params[0].tags.map(&.name)
      tag_names.should contain("sqli")
    end

    it "tags IDOR vulnerable parameters" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/profile", "GET", [
        Param.new("user", "john", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.size.should be >= 1
      tag_names = endpoint.params[0].tags.map(&.name)
      tag_names.should contain("idor")
    end

    it "tags file inclusion vulnerable parameters" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/download", "GET", [
        Param.new("file", "document.pdf", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.size.should eq(1)
      endpoint.params[0].tags[0].name.should eq("file-inclusion")
    end

    it "tags debug vulnerable parameters" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/admin", "GET", [
        Param.new("debug", "true", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.size.should eq(1)
      endpoint.params[0].tags[0].name.should eq("debug")
    end

    it "tags command injection vulnerable parameters" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/exec", "POST", [
        Param.new("cmd", "ls", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.size.should eq(1)
      endpoint.params[0].tags[0].name.should eq("command-injection")
    end

    it "does not tag safe parameters" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/data", "GET", [
        Param.new("page_number", "1", "query"),
        Param.new("items_per_page", "10", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.size.should eq(0)
      endpoint.params[1].tags.size.should eq(0)
    end

    it "can tag multiple parameters in one endpoint" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/search", "GET", [
        Param.new("query", "test", "query"),
        Param.new("file", "results.xml", "query"),
        Param.new("debug", "true", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.size.should be >= 1
      endpoint.params[1].tags.size.should eq(1)
      endpoint.params[2].tags.size.should eq(1)
    end

    it "handles multiple endpoints" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint1 = Endpoint.new("/user", "GET", [
        Param.new("id", "123", "query"),
      ])

      endpoint2 = Endpoint.new("/api/safe", "GET", [
        Param.new("count", "10", "query"),
      ])

      tagger.perform([endpoint1, endpoint2])

      endpoint1.params[0].tags.size.should be >= 1
      endpoint2.params[0].tags.size.should eq(0)
    end
  end
end
