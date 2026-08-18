require "../../spec_helper"
require "yaml"
require "../../../src/models/deliver"
require "../../../src/models/endpoint"

# Filling a path template is pure string work, so it gets direct coverage here
# rather than being inferred from whatever a capturing server happened to
# receive. `probe_url` is protected; this subclass is the only reason it can
# be called from a spec.
private class ProbeUrlProbe < Deliver
  def url_for(endpoint : Endpoint, request_method : String = "GET") : String
    probe_url(endpoint, request_method)
  end
end

private def path_endpoint(url : String, *names : String) : Endpoint
  endpoint = Endpoint.new(url, "GET")
  names.each { |name| endpoint.params << Param.new(name, "", "path") }
  endpoint
end

describe "Deliver#probe_url" do
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(".")])
  probe = ProbeUrlProbe.new(options)

  describe "the Express-style :name form" do
    it "fills a lone :name" do
      probe.url_for(path_endpoint("http://h/users/:id", "id")).should eq("http://h/users/1")
    end

    # The bug: `:name` has no closing delimiter, so `:id` matched the head of
    # `:idx`. Params are visited in declaration order, so the shorter name won
    # and the probe went to `/u/1/1x` — a path the app does not route.
    it "does not let a shorter param name eat a longer one that starts with it" do
      endpoint = path_endpoint("http://h/u/:id/:idx", "id", "idx")
      probe.url_for(endpoint).should eq("http://h/u/1/1")
    end

    it "fills the same pair correctly with the names declared the other way round" do
      endpoint = path_endpoint("http://h/u/:idx/:id", "idx", "id")
      probe.url_for(endpoint).should eq("http://h/u/1/1")
    end

    # The trailing boundary has to admit the suffixes the no-boundary version
    # existed to support, so it stops at the first character that cannot be
    # part of a name rather than requiring `/` or end-of-string.
    it "still fills Play-style /:lang.json" do
      probe.url_for(path_endpoint("http://h/:lang.json", "lang")).should eq("http://h/noir.json")
    end

    it "still fills a :name followed by a - suffix" do
      probe.url_for(path_endpoint("http://h/posts/:id-preview", "id")).should eq("http://h/posts/1-preview")
    end

    it "leaves a longer name alone when only the shorter one is declared" do
      # Only `:id` is a real param here, so `:idx` is not a placeholder this
      # endpoint knows about and must survive untouched.
      probe.url_for(path_endpoint("http://h/u/:id/:idx", "id")).should eq("http://h/u/1/:idx")
    end

    it "treats a name containing regex metacharacters literally" do
      # `Regex.escape` is what keeps `.` from matching any character; the
      # trailing lookahead must not undo that.
      probe.url_for(path_endpoint("http://h/f/:a.b/x", "a.b")).should eq("http://h/f/noir/x")
      probe.url_for(path_endpoint("http://h/f/:a+b", "a+b")).should eq("http://h/f/noir")
    end

    it "keeps the port colon and mid-segment text out of it" do
      endpoint = path_endpoint("http://host:8080/profiles/celeb_:USERNAME", "USERNAME")
      probe.url_for(endpoint).should eq("http://host:8080/profiles/celeb_:USERNAME")
    end
  end

  describe "the delimited forms" do
    it "fills {name} and <name> without prefix collisions" do
      braces = path_endpoint("http://h/u/{id}/{idx}", "id", "idx")
      probe.url_for(braces).should eq("http://h/u/1/1")

      angles = path_endpoint("http://h/u/<id>/<idx>", "id", "idx")
      probe.url_for(angles).should eq("http://h/u/1/1")
    end
  end

  it "leaves the template alone for destructive verbs" do
    endpoint = path_endpoint("http://h/u/:id/:idx", "id", "idx")
    probe.url_for(endpoint, "DELETE").should eq("http://h/u/:id/:idx")
  end

  it "does not touch a param --set-pvalue-path already resolved" do
    endpoint = Endpoint.new("http://h/u/42/:idx", "GET")
    endpoint.params << Param.new("id", "42", "path")
    endpoint.params << Param.new("idx", "", "path")

    probe.url_for(endpoint).should eq("http://h/u/42/1")
  end
end
