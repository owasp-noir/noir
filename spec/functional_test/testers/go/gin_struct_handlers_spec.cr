require "../../func_spec.cr"

# Gin routes whose handlers are methods of struct values declared in the
# router (`itemHandler := api.ItemAPI{}`) and defined in another package.
# `Match` registers one route per verb; an empty path is the group's own
# path; a group named `client` is still a group. A handler factory
# (`serveFile("index.html")`) answers with the closure it returns. Bind
# targets read as their struct's tagged fields: `ShouldBindJSON` json tags,
# `MustBindWith(p, binding.Query)` form tags as query, `Bind` on a body json
# and form tags (`form:"-"` is json-only), `ShouldBindUri` uri tags. An
# untagged exported field binds by its own name, as gin's form mapping and
# encoding/json do.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/health", "HEAD"),
  Endpoint.new("/page", "GET"),
  Endpoint.new("/message", "POST", [Param.new("title", "", "json"), Param.new("message", "", "json"), Param.new("Note", "", "json")]),
  Endpoint.new("/public", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/signup", "POST", [Param.new("email", "", "form")]),
  Endpoint.new("/login", "POST", [Param.new("user", "", "form")]),
  Endpoint.new("/items", "GET", [Param.new("limit", "", "query"), Param.new("since", "", "query")]),
  Endpoint.new("/items/:id", "PUT", [
    Param.new("id", "", "path"),
    Param.new("name", "", "json"),
    Param.new("name", "", "form"),
    Param.new("priority", "", "json"),
    Param.new("extras", "", "json"),
    Param.new("Owner", "", "json"),
    Param.new("Owner", "", "form"),
  ]),
  Endpoint.new("/client/:id", "GET", [Param.new("id", "", "path")]),
]

tester = FunctionalTester.new("fixtures/go/gin_struct_handlers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "gin struct-value handlers", tags: "functional" do
  base = "./spec/functional_test/fixtures/go/gin_struct_handlers"

  it "resolves a method value on a local of another package's struct" do
    health = tester.app.endpoints.find! { |ep| ep.url == "/health" && ep.method == "HEAD" }
    health.handler.should eq(Handler.new("itemHandler.Health", "#{base}/api/api.go", 23))
    update = tester.app.endpoints.find! { |ep| ep.url == "/items/:id" }
    update.handler.should eq(Handler.new("itemHandler.UpdateItem", "#{base}/api/api.go", 54))
  end

  it "names the closure a handler factory returns" do
    page = tester.app.endpoints.find! { |ep| ep.url == "/page" }
    page.handler.should eq(Handler.new("serveFile", "#{base}/router/router.go", 38))
  end

  it "reads bind targets as their tagged fields, not a body marker" do
    tester.app.endpoints.each { |ep| ep.params.map(&.name).should_not contain("body") }
    update = tester.app.endpoints.find! { |ep| ep.url == "/items/:id" }
    # `form:"-"` is not form-bound.
    update.params.any? { |p| p.name == "extras" && p.param_type == "form" }.should be_false
  end
end
