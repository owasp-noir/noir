require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "json"),
  ]),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("filter", "", "query"),
  ]),
  Endpoint.new("/users/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("name", "", "json"),
  ]),
  Endpoint.new("/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("soft", "", "query"),
  ]),
  Endpoint.new("/api/reports", "GET", [
    Param.new("X-Trace-Id", "", "header"),
  ]),
  Endpoint.new("/api/reports/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("sid", "", "cookie"),
  ]),
  Endpoint.new("/api/reports/bulk", "PATCH", [
    Param.new("payload", "", "form"),
  ]),
  Endpoint.new("/api/reports/bulk", "POST", [
    Param.new("payload", "", "form"),
  ]),
  Endpoint.new("/admin/notify", "POST", [
    Param.new("subject", "", "form"),
  ]),
  # `class DirectorsModule : CarterModule` with `: base("/directors")` — every
  # route in the module hangs off the constructor base path.
  Endpoint.new("/directors", "GET"),
  Endpoint.new("/directors", "PUT", [
    Param.new("person", "", "json"),
  ]),
  Endpoint.new("/directors/qs", "GET", [
    Param.new("name", "", "query"),
    Param.new("numbers", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/csharp/carter/", {
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "Carter analyzer edge cases" do
  it "does not surface routes from /test/ fixtures" do
    tester.app.endpoints.any?(&.url.includes?("test-only")).should be_false
  end

  it "claims CarterModule-derived modules instead of leaving them to the minimal-API analyzer" do
    directors = tester.app.endpoints.find { |e| e.url == "/directors" && e.method == "GET" }
    directors.should_not be_nil
    directors.as(Endpoint).details.technology.should eq "cs_carter"
    # The un-prefixed route the minimal-API analyzer used to emit.
    tester.app.endpoints.any? { |e| e.url == "/qs" }.should be_false
  end

  it "ignores a commented-out route registration" do
    tester.app.endpoints.any?(&.url.includes?("commented-out")).should be_false
  end

  it "marks Carter modules with the cs_carter technology" do
    users = tester.app.endpoints.find { |e| e.url == "/users" && e.method == "GET" }
    users.should_not be_nil
    users.as(Endpoint).details.technology.should eq "cs_carter"
  end
end
