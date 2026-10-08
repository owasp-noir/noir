require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/hello/:name", "GET", [Param.new("name", "", "path")]),
  Endpoint.new("/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("limit", "", "query"),
    Param.new("X-Token", "", "header"),
  ]),
  # No path: /<service>.<export>, the service named in encore.service.ts; no method: POST.
  Endpoint.new("/greeter.create", "POST", [
    Param.new("title", "", "json"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/posts/:id", "PUT", [Param.new("id", "", "path"), Param.new("title", "", "json")]),
  Endpoint.new("/posts/:id", "PATCH", [Param.new("id", "", "path"), Param.new("title", "", "json")]),
  Endpoint.new("/hooks/*rest", "ANY", [Param.new("rest", "", "path")]),
  Endpoint.new("/chat", "GET", [Param.new("room", "", "query")]),
  Endpoint.new("/static/*path", "GET", [Param.new("path", "", "path")]),
  # The `!path` fallback is reported as a `*path` wildcard.
  Endpoint.new("/*path", "GET", [Param.new("path", "", "path")]),
  Endpoint.new("/admin/stats", "GET"),
]

FunctionalTester.new("fixtures/typescript/encore/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Encore.ts endpoint flags", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "tags access and auth, and marks streams as WebSocket" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/typescript/encore/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    find = ->(method : String, url : String) { app.endpoints.find! { |ep| ep.method == method && ep.url == url } }
    tags = ->(method : String, url : String) { find.call(method, url).tags.map { |tag| {tag.name, tag.description} } }

    tags.call("GET", "/hello/:name").should eq [{"encore-access", "public"}]
    tags.call("POST", "/greeter.create").should contain({"auth", "Encore auth endpoint"})
    tags.call("GET", "/admin/stats").should eq [{"encore-access", "private"}]
    find.call("GET", "/chat").protocol.should eq "ws"
    find.call("GET", "/search").protocol.should eq "http"
  end
end
