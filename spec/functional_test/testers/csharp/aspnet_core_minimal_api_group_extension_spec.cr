require "../../func_spec.cr"

# Routes registered inside a `this RouteGroupBuilder` extension method take
# the `MapGroup` prefix of every call site, across files and nested calls.
expected_endpoints = [
  Endpoint.new("/public/todos", "GET"),
  Endpoint.new("/public/todos/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/public/todos", "POST", [Param.new("todo", "", "json")]),
  Endpoint.new("/private/todos", "GET"),
  Endpoint.new("/private/todos/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/private/todos", "POST", [Param.new("todo", "", "json")]),
  Endpoint.new("/api/v1/admin/stats", "GET"),
  Endpoint.new("/api/v1/admin/users/{id}", "DELETE", [Param.new("id", "", "path")]),
]

tester = FunctionalTester.new("fixtures/csharp/aspnet_core_minimal_api_group_extension/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "ASP.NET Core Minimal API route-group extension methods", tags: "functional" do
  it "drops the DbContext injected into the handlers" do
    tester.app.endpoints.any? { |e| e.params.any? { |p| p.name == "database" } }.should be_false
  end
end
