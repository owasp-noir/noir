require "../../func_spec.cr"
require "../../../../src/cli/inspect"

# FastRoute patterns as Slim apps write them: a trailing optional part
# `[...]` is one route per variant, and a `{name:regex}` constraint decides
# which route a request reaches, so it stays in the URL.
expected_endpoints = [
  Endpoint.new("/{routes:.+}", "OPTIONS", [Param.new("routes", "", "path")]),
  Endpoint.new("/news", "GET"),
  Endpoint.new("/news/{year:[0-9]{4}}", "GET", [Param.new("year", "", "path")]),
  Endpoint.new("/news/{year:[0-9]{4}}/{month:[0-9]{2}}", "GET", [
    Param.new("year", "", "path"),
    Param.new("month", "", "path"),
  ]),
  Endpoint.new("/users/{id:[0-9]+}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{name}", "GET", [Param.new("name", "", "path")]),
  Endpoint.new("/books", "GET"),
  Endpoint.new("/books", "DELETE"),
  Endpoint.new("/books/{id:\\d+}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/books/{id:\\d+}", "DELETE", [Param.new("id", "", "path")]),
]

tester = FunctionalTester.new("fixtures/php/slim_route_patterns/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Slim FastRoute patterns", tags: "functional" do
  trace = ->(method : String, path : String) do
    Noir::CLI::Inspect.trace(tester.app.endpoints, method, path).map(&.endpoint.url)
  end

  it "reads no path param out of a regex quantifier" do
    tester.app.endpoints.flat_map(&.params.map(&.name)).uniq!.sort!.should eq(["id", "month", "name", "routes", "year"])
  end

  it "traces each variant of an optional part and honours its constraints" do
    trace.call("GET", "/news").should eq(["/news"])
    trace.call("GET", "/news/2024").should eq(["/news/{year:[0-9]{4}}"])
    trace.call("GET", "/news/2024/05").should eq(["/news/{year:[0-9]{4}}/{month:[0-9]{2}}"])
    trace.call("GET", "/news/latest").should be_empty
    trace.call("DELETE", "/books/7").should eq(["/books/{id:\\d+}"])
  end

  it "traces a request to the route its constraint selects" do
    trace.call("GET", "/users/42").first.should eq("/users/{id:[0-9]+}")
    trace.call("GET", "/users/bob").should eq(["/users/{name}"])
    trace.call("OPTIONS", "/api/v1/anything").should eq(["/{routes:.+}"])
  end
end
