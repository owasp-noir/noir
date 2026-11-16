require "../../func_spec.cr"
require "../../../../src/cli/inspect"

# `route` is Grape's verb DSL with the methods spelled out: a list registers
# the route once per method, `:any` for every method.
item_params = [
  Param.new("id", "", "path"),
  Param.new("name", "", "json"),
  Param.new("note", "", "query"),
]

expected_endpoints = [
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/bulk", "GET"),
  Endpoint.new("/api/bulk", "POST"),
  Endpoint.new("/api/items/{id}", "PUT", item_params),
  Endpoint.new("/api/items/{id}", "PATCH", item_params),
  Endpoint.new("/api/*path", "ANY", [Param.new("path", "", "path")]),
]

tester = FunctionalTester.new("fixtures/ruby/grape_route_methods/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Grape format suffix", tags: "functional" do
  # Grape compiles every route with an optional `(.:format)` suffix.
  it "traces a request carrying a format extension to its route, ahead of the catch-all" do
    trace = ->(method : String, path : String) do
      Noir::CLI::Inspect.trace(tester.app.endpoints, method, path).map(&.endpoint.url)
    end

    trace.call("GET", "/api/status.json").should eq(["/api/status", "/api/*path"])
    trace.call("POST", "/api/bulk.json").first.should eq("/api/bulk")
    trace.call("DELETE", "/api/nowhere").should eq(["/api/*path"])
  end
end
