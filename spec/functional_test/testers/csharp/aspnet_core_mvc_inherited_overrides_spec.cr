require "../../func_spec.cr"

# An `override` without routing attributes keeps the overridden action's
# `[HttpGet("{id}")]`; it is not a conventional action at the controller
# route. One that redeclares its attributes is its own.
expected_endpoints = [
  Endpoint.new("/api/Widgets", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/Widgets/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/Widgets", "POST", [Param.new("item", "", "json")]),
  Endpoint.new("/api/Widgets/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/Widgets/search", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/api/Gadgets", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/Gadgets/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/Gadgets", "POST", [Param.new("item", "", "json")]),
  Endpoint.new("/api/Gadgets/{id}", "DELETE", [Param.new("id", "", "path")]),
]

tester = FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_inherited_overrides/", {
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "ASP.NET Core MVC attribute-less overrides", tags: "functional" do
  it "does not fold the override into the collection route" do
    widgets = tester.app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/Widgets" }
    widgets.params.map(&.name).should eq(["page"])
  end
end
