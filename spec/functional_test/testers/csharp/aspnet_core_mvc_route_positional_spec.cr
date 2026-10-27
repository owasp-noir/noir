require "../../func_spec.cr"

# Positional `MapControllerRoute(name, pattern[, defaults])` and
# `MapAreaControllerRoute(name, area, pattern)` in the host, which owns its
# routing table: an area no declared route reaches is not given one, and
# templates that cannot be read (a parameter, a method with branching
# returns, a concatenation) are skipped.
expected_endpoints = [
  Endpoint.new("/Home/Index", "GET"),
  Endpoint.new("/blog/Index", "GET"),
  Endpoint.new("/Home/Details/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/blog/Details", "GET", [Param.new("id", "", "query")]),
  Endpoint.new("/Admin/Dashboard/Index", "GET"),
  # The library's unreadable templates are skipped; it keeps the default route.
  Endpoint.new("/Tools/Details/{id}", "GET", [Param.new("id", "", "path")]),
]

tester = FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_route_positional/", {
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "ASP.NET Core MVC positional route templates", tags: "functional" do
  it "reports no route for an area the host's table does not reach" do
    tester.app.endpoints.any?(&.url.includes?("Cart")).should be_false
  end

  it "does not read a parameter, a branching method or a concatenation" do
    urls = tester.app.endpoints.map(&.url)
    urls.any? { |url| url.includes?("wrong") || url.includes?("/en/") || url.includes?("zone") || url.includes?("pre") }.should be_false
  end
end
