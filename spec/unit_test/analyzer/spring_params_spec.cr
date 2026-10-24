require "../../spec_helper"
require "../../../src/models/noir"

# Exact Spring params per route for the `java/spring_params` fixture
# (#3083 #3084 #3085 #3086 #3091). Functional testers only assert presence;
# most of these bugs were phantom or mislocated params.
private def spring_params_scan : Hash(String, Array(String))
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(File.expand_path("../../functional_test/fixtures/java/spring_params", __DIR__))])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints.to_h do |endpoint|
    {"#{endpoint.method} #{endpoint.url}",
     endpoint.params.map { |p| p.value.empty? ? "#{p.name}:#{p.param_type}" : "#{p.name}:#{p.param_type}=#{p.value}" }}
  end
ensure
  CodeLocator.instance.reset_files
end

describe "Spring parameter binding" do
  routes = spring_params_scan

  it "drops a parameter annotated with a custom @AuthenticationPrincipal meta-annotation (#3083)" do
    routes["GET /widgets/mine"].should eq([] of String)
  end

  it "emits one named param for enum / value-class @RequestParam and @RequestHeader (#3084)" do
    routes["GET /k/a"].should eq(["kind:query"])
    routes["GET /k/b"].should eq(["kind:query"])
    routes["GET /k/c"].should eq(["kind:query"])
    routes["GET /k/d"].should eq(["code:query"])
    routes["GET /k/f"].should eq(["flt:query"])
    routes["GET /k/g"].should eq(["X-Color:header"])
    routes["GET /k/h"].should eq([] of String)
  end

  it "models multipart files and @RequestPart as named form parts (#3085)" do
    routes["POST /avatar"].should eq(["img:form", "label:query"])
    routes["POST /avatar2"].should eq(["img:form"])
    routes["POST /upload"].should eq(["meta:form", "blob:form"])
    routes["PUT /upload"].should eq(["meta:form", "blobs:form"])
  end

  it "expands nested command-object fields to dotted names unless a Formatter converts them, independent of argument order (#3086)" do
    routes["GET /search"].should eq(["keyword:query", "pager.offset:query", "pager.limit:query", "tag:query", "uploads:form"])
    routes["POST /save"].should eq(["payload:query", "keyword:form", "pager.offset:form", "pager.limit:form", "tag:form", "uploads:form"])
    routes["POST /save2"].should eq(["keyword:form", "pager.offset:form", "pager.limit:form", "tag:form", "uploads:form"])
  end

  it "skips mapping annotations on a non-controller bean (#3091)" do
    routes.has_key?("POST /lookup").should be_false
  end

  it "scans HttpServletRequest getters whatever the argument order (#3091)" do
    routes["POST /pick/{slot}"].should eq(["X-Back:header", "flavor:form", "slot:path"])
    routes["POST /pick2"].should eq(["a:query", "flavor:form"])
  end

  it "reads literal keys off a @RequestParam / @RequestHeader map, and request getters in a same-class helper" do
    routes["DELETE /series"].should eq(["keys:query", "key:query"])
    routes["GET /trace"].should eq(["X-Trace:header"])
    routes["GET /fwd"].should eq(["X-Forwarded-Proto:header"])
  end

  it "emits Pageable's page/size/sort with @PageableDefault values (#3091)" do
    routes["GET /paged"].should eq(["q:query", "page:query", "size:query", "sort:query"])
    routes["GET /paged2"].should eq(["page:query", "size:query=20", "sort:query=id"])
  end
end
