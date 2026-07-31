require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("req", "", "json"),
  ]),
  Endpoint.new("/users/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("req", "", "json"),
  ]),
  Endpoint.new("/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("soft", "", "query"),
  ]),
  Endpoint.new("/users/{id}", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("X-Trace-Id", "", "header"),
    Param.new("sid", "", "cookie"),
  ]),
  Endpoint.new("/fallback", "ANY"),
  Endpoint.new("/bulk", "PUT"),
  Endpoint.new("/bulk", "PATCH"),
  Endpoint.new("/api/v1/products/{sku}", "GET", [
    Param.new("sku", "", "path"),
    Param.new("X-Mode", "", "header"),
  ]),
  Endpoint.new("/nested/v2/orders", "POST", [
    Param.new("order", "", "json"),
  ]),
  Endpoint.new("/inline/submit", "POST", [
    Param.new("req", "", "json"),
  ]),
  # `async context => …` is the RequestDelegate overload: `context` is the
  # HttpContext, not a query value.
  Endpoint.new("/raw", "GET"),
]

tester = FunctionalTester.new("fixtures/csharp/aspnet_core_minimal_api/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "ASP.NET Core Minimal API analyzer edge cases" do
  it "does not register routes written inside comments" do
    tester.app.endpoints.any?(&.url.includes?("doc-only")).should be_false
    tester.app.endpoints.any?(&.url.includes?("commented-out")).should be_false
  end

  it "drops an untyped lambda parameter instead of reporting it as a query param" do
    raw = tester.app.endpoints.find { |e| e.url == "/raw" && e.method == "GET" }
    raw.should_not be_nil
    raw.as(Endpoint).params.empty?.should be_true
  end

  it "marks minimal API routes with the dedicated technology" do
    users = tester.app.endpoints.find { |e| e.url == "/users" && e.method == "GET" }
    users.should_not be_nil
    users.as(Endpoint).details.technology.should eq "cs_aspnet_core_minimal_api"
  end
end
