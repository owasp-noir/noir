require "../../../src/models/endpoint.cr"

describe "Initialize 2 arguments" do
  endpoint = Endpoint.new("/abcd", "GET")
  it "detect_url" do
    endpoint.url.should eq("/abcd")
  end
  it "detect_method" do
    endpoint.method.should eq("GET")
  end
  it "detect_params" do
    endpoint.params.should eq([] of Param)
  end
  it "has no ai_context by default" do
    endpoint.ai_context.should be_nil
  end
end

describe "Initialize 3 arguments" do
  endpoint = Endpoint.new("/abcd", "GET", [Param.new("a", "b", "query")])
  it "detect_url" do
    endpoint.url.should eq("/abcd")
  end
  it "detect_method" do
    endpoint.method.should eq("GET")
  end
  it "detect_params" do
    endpoint.params.should eq([Param.new("a", "b", "query")])
  end

  path = "path/a/b/c"
  line = 123
  path_info = PathInfo.new(path, line)
  endpoint2 = Endpoint.new("/abcd", "GET", Details.new(path_info))
  it "detect_url" do
    endpoint2.url.should eq("/abcd")
  end
  it "detect_method" do
    endpoint2.method.should eq("GET")
  end
  it "detect_details" do
    endpoint2.details.should eq(Details.new(path_info))
    endpoint2.details.code_paths[0].path.should eq(path)
    endpoint2.details.code_paths[0].line.should eq(line)
  end
end

describe "Initialize 4 arguments" do
  path = "path/a/b/c"
  line = 123
  path_info = PathInfo.new(path, line)
  endpoint = Endpoint.new("/abcd", "GET", [Param.new("a", "b", "query")], Details.new(path_info))
  it "detect_url" do
    endpoint.url.should eq("/abcd")
  end
  it "detect_method" do
    endpoint.method.should eq("GET")
  end
  it "detect_params" do
    endpoint.params.should eq([Param.new("a", "b", "query")])
  end
  it "detect_details" do
    endpoint.details.should eq(Details.new(path_info))
    endpoint.details.code_paths[0].path.should eq(path)
    endpoint.details.code_paths[0].line.should eq(line)
  end
end

describe "Endpoint detail ownership" do
  it "does not share mutable code paths from reused Details" do
    shared_details = Details.new(PathInfo.new("openapi.json", 1))

    first = Endpoint.new("/first", "GET", shared_details)
    second = Endpoint.new("/second", "GET", shared_details)

    first.details.add_path(PathInfo.new("first_controller.py", 10))

    first.details.code_paths.map(&.path).should eq(["openapi.json", "first_controller.py"])
    second.details.code_paths.map(&.path).should eq(["openapi.json"])
  end

  it "does not share mutable tags from reused Params" do
    param = Param.new("token", "", "header")
    first = Endpoint.new("/first", "GET", [param])
    second = Endpoint.new("/second", "GET", [param])

    first.params[0].add_tag(Tag.new("auth", "", "test"))

    first.params[0].tags.size.should eq(1)
    second.params[0].tags.should be_empty
  end
end

describe "Endpoint equality" do
  it "same endpoints" do
    endpoint1 = Endpoint.new("/abcd", "GET")
    endpoint2 = Endpoint.new("/abcd", "GET")
    (endpoint1 == endpoint2).should be_true
  end

  it "different endpoints" do
    endpoint1 = Endpoint.new("/abcd", "GET")
    endpoint2 = Endpoint.new("/abcd", "POST")
    (endpoint1 == endpoint2).should be_false
  end

  it "same endpoints with params" do
    endpoint1 = Endpoint.new("/abcd", "GET", [Param.new("a", "b", "query")])
    endpoint2 = Endpoint.new("/abcd", "GET", [Param.new("a", "b", "query")])
    (endpoint1 == endpoint2).should be_true
  end

  it "different endpoints with params" do
    endpoint1 = Endpoint.new("/abcd", "GET", [Param.new("a", "b", "query")])
    endpoint2 = Endpoint.new("/abcd", "GET", [Param.new("a", "b", "json")])
    (endpoint1 == endpoint2).should be_false
  end

  it "same endpoints and shuffled params" do
    endpoint1 = Endpoint.new("/abcd", "GET", [Param.new("a", "b", "query"), Param.new("c", "d", "json")])
    endpoint2 = Endpoint.new("/abcd", "GET", [Param.new("c", "d", "json"), Param.new("a", "b", "query")])
    (endpoint1 == endpoint2).should be_true
  end

  describe "#push_callee" do
    it "stops accepting callees after MAX_PER_ENDPOINT" do
      endpoint = Endpoint.new("/cap", "GET")
      (Callee::MAX_PER_ENDPOINT + 5).times do |i|
        endpoint.push_callee(Callee.new("fn#{i}"))
      end
      endpoint.callees.size.should eq Callee::MAX_PER_ENDPOINT
    end

    it "drops the late arrivals, not the early ones" do
      endpoint = Endpoint.new("/cap", "GET")
      (Callee::MAX_PER_ENDPOINT + 3).times do |i|
        endpoint.push_callee(Callee.new("fn#{i}"))
      end
      endpoint.callees.first.name.should eq "fn0"
      endpoint.callees.last.name.should eq "fn#{Callee::MAX_PER_ENDPOINT - 1}"
    end

    it "dedups by (name, path)" do
      endpoint = Endpoint.new("/dup", "GET")
      endpoint.push_callee(Callee.new("save", path: "app.py", line: 10))
      endpoint.push_callee(Callee.new("save", path: "app.py", line: 10))
      endpoint.push_callee(Callee.new("save", path: "app.py", line: 11))
      endpoint.push_callee(Callee.new("save", path: "other.py", line: 10))
      endpoint.callees.size.should eq 2
    end
  end

  describe "#push_param" do
    it "dedups by (name, param_type) but keeps distinct params" do
      endpoint = Endpoint.new("/p", "GET")
      endpoint.push_param(Param.new("id", "", "query"))
      endpoint.push_param(Param.new("id", "later", "query")) # dup (name, type) — dropped
      endpoint.push_param(Param.new("id", "", "path"))       # same name, different type — kept
      endpoint.push_param(Param.new("name", "", "query"))    # different name — kept

      endpoint.params.size.should eq 3
      endpoint.params.count { |p| p.name == "id" && p.param_type == "query" }.should eq 1
      endpoint.params.count { |p| p.name == "id" && p.param_type == "path" }.should eq 1
    end
  end

  describe "#add_tag" do
    it "dedups by (name, tagger) but keeps distinct tags" do
      endpoint = Endpoint.new("/tagged", "GET")
      endpoint.add_tag(Tag.new("auth", "desc", "django_auth"))
      endpoint.add_tag(Tag.new("auth", "desc again", "django_auth")) # dup (name, tagger)
      endpoint.add_tag(Tag.new("auth", "desc", "spring_auth"))       # different tagger
      endpoint.add_tag(Tag.new("jwt", "desc", "JWT"))                # different name

      endpoint.tags.size.should eq 3
      endpoint.tags.count { |t| t.name == "auth" && t.tagger == "django_auth" }.should eq 1
    end
  end
end

describe AIContext do
  it "is empty by default" do
    AIContext.new.empty?.should be_true
  end

  it "is not empty after a push" do
    ctx = AIContext.new
    ctx.push_guard(AIContextEntry.new("guard", "auth"))
    ctx.empty?.should be_false
  end

  it "dedups identical entries within a bucket" do
    ctx = AIContext.new
    ctx.push_source(AIContextEntry.new("src", "body", path: "app.py", line: 10))
    ctx.push_source(AIContextEntry.new("src", "body", path: "app.py", line: 10))
    ctx.sources.size.should eq 1
  end

  it "keeps entries that differ only by name" do
    ctx = AIContext.new
    ctx.push_source(AIContextEntry.new("src", "body"))
    ctx.push_source(AIContextEntry.new("src", "query"))
    ctx.sources.size.should eq 2
  end

  it "caps a bucket at MAX_PER_SECTION" do
    ctx = AIContext.new
    (AIContext::MAX_PER_SECTION + 5).times do |i|
      ctx.push_sink(AIContextEntry.new("sink", "s#{i}"))
    end
    ctx.sinks.size.should eq AIContext::MAX_PER_SECTION
  end

  it "drops the late arrivals, not the early ones" do
    ctx = AIContext.new
    (AIContext::MAX_PER_SECTION + 3).times do |i|
      ctx.push_sink(AIContextEntry.new("sink", "s#{i}"))
    end
    ctx.sinks.first.name.should eq "s0"
    ctx.sinks.last.name.should eq "s#{AIContext::MAX_PER_SECTION - 1}"
  end
end
