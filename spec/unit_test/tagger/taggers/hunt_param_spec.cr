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

    it "does not treat bare query parameters as SQLi by default" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/users", "GET", [
        Param.new("query", "select * from users", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.map(&.name).should_not contain("sqli")
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

    it "keeps generic id parameters focused on IDOR heuristics" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/users/:id", "GET", [
        Param.new("id", "123", "path"),
      ])

      tagger.perform([endpoint])

      tag_names = endpoint.params[0].tags.map(&.name)
      tag_names.should contain("idor")
      tag_names.should_not contain("sqli")
      tag_names.should_not contain("ssti")
    end

    it "does not tag body ids as Hunt IDOR by default" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/items", "POST", [
        Param.new("id", "123", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.map(&.name).should_not contain("idor")
    end

    it "does not tag bare body keys as Hunt IDOR by default" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/items", "POST", [
        Param.new("key", "catalog-key", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.map(&.name).should_not contain("idor")
    end

    it "keeps path keys as Hunt IDOR candidates" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/cache/{key}", "DELETE", [
        Param.new("key", "entry", "path"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.map(&.name).should contain("idor")
    end

    it "does not tag emails as Hunt IDOR by default" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/register", "POST", [
        Param.new("email", "user@example.com", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.map(&.name).should_not contain("idor")
    end

    it "does not treat common name fields as SSTI or SQLi by default" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/profile", "POST", [
        Param.new("name", "alice", "json"),
      ])

      tagger.perform([endpoint])

      tag_names = endpoint.params[0].tags.map(&.name)
      tag_names.should_not contain("ssti")
      tag_names.should_not contain("sqli")
    end

    it "does not treat plain content fields as SSTI by default" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/posts", "POST", [
        Param.new("content", "hello", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.map(&.name).should_not contain("ssti")
    end

    it "does not treat role flags as SQLi by default" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/admin/users", "POST", [
        Param.new("role", "admin", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.map(&.name).should_not contain("sqli")
    end

    it "does not treat generic from filters as SQLi by default" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/analytics", "GET", [
        Param.new("from", "2025-01-01", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.map(&.name).should_not contain("sqli")
    end

    it "keeps sort controls tagged as SQLi-oriented query builder inputs" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/reviews", "GET", [
        Param.new("sort", "created_at", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.map(&.name).should contain("sqli")
    end

    it "does not treat view switches as SSTI or SSRF by default" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/dashboard", "GET", [
        Param.new("view", "summary", "query"),
      ])

      tagger.perform([endpoint])

      tag_names = endpoint.params[0].tags.map(&.name)
      tag_names.should_not contain("ssti")
      tag_names.should_not contain("ssrf")
      tag_names.should_not contain("sqli")
    end

    it "keeps path users focused on IDOR heuristics" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/users/:user", "GET", [
        Param.new("user", "alice", "path"),
      ])

      tagger.perform([endpoint])

      tag_names = endpoint.params[0].tags.map(&.name)
      tag_names.should contain("idor")
      tag_names.should_not contain("sqli")
    end

    it "treats camelCase path ids as IDOR-oriented identifiers" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/payments/:methodId", "GET", [
        Param.new("methodId", "card", "path"),
      ])

      tagger.perform([endpoint])

      tag_names = endpoint.params[0].tags.map(&.name)
      tag_names.should contain("idor")
      tag_names.should_not contain("sqli")
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

    it "can tag multiple parameters in one endpoint while leaving generic query names alone" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/search", "GET", [
        Param.new("query", "test", "query"),
        Param.new("file", "results.xml", "query"),
        Param.new("debug", "true", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.size.should eq(0)
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

    it "does not add duplicate Hunt tags that already exist" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/users/:id", "GET", [
        Param.new("id", "123", "path"),
      ])
      endpoint.params[0].add_tag(Tag.new("idor", "existing", "Hunt"))

      tagger.perform([endpoint])

      endpoint.params[0].tags.count { |tag| tag.name == "idor" && tag.tagger == "Hunt" }.should eq(1)
    end

    it "matches parameter names case-insensitively" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/fetch", "GET", [
        Param.new("URL", "http://example.com", "query"),
        Param.new("File", "report.pdf", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.any? { |t| t.name == "ssrf" && t.tagger == "Hunt" }.should be_true
      endpoint.params[1].tags.any? { |t| t.name == "file-inclusion" && t.tagger == "Hunt" }.should be_true
    end

    it "suppresses bare id IDOR for body params just like json/form" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/update", "POST", [
        Param.new("id", "123", "body"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.any? { |t| t.name == "idor" && t.tagger == "Hunt" }.should be_false
    end

    it "tags compound url/uri parameter names as SSRF" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/proxy", "POST", [
        Param.new("redirectUrl", "http://example.com", "query"),
        Param.new("callback_uri", "http://example.com", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.any? { |t| t.name == "ssrf" && t.tagger == "Hunt" }.should be_true
      endpoint.params[1].tags.any? { |t| t.name == "ssrf" && t.tagger == "Hunt" }.should be_true
    end

    it "does not treat curl-like names ending in url as SSRF" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/run", "POST", [
        Param.new("curl", "1", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.map(&.name).should_not contain("ssrf")
    end

    it "tags compound identifier query parameters as IDOR" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/orders", "GET", [
        Param.new("userId", "42", "query"),
        Param.new("account_id", "7", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.any? { |t| t.name == "idor" && t.tagger == "Hunt" }.should be_true
      endpoint.params[1].tags.any? { |t| t.name == "idor" && t.tagger == "Hunt" }.should be_true
    end

    it "does not promote compound body identifiers to IDOR" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/update", "POST", [
        Param.new("userId", "42", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.map(&.name).should_not contain("idor")
    end

    it "tags compound file parameter names as file inclusion" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/download", "GET", [
        Param.new("file_path", "/etc/passwd", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.any? { |t| t.name == "file-inclusion" && t.tagger == "Hunt" }.should be_true
    end

    it "does not treat a bare number parameter as IDOR" do
      tagger = HuntParamTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/page", "GET", [
        Param.new("number", "5", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.params[0].tags.map(&.name).should_not contain("idor")
    end
  end
end
