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
]

tester = FunctionalTester.new("fixtures/csharp/carter/", {
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "Carter analyzer edge cases" do
  it "does not surface routes from /test/ fixtures" do
    tester.app.endpoints.any?(&.url.includes?("test-only")).should be_false
  end

  it "marks Carter modules with the cs_carter technology" do
    users = tester.app.endpoints.find { |e| e.url == "/users" && e.method == "GET" }
    users.should_not be_nil
    users.as(Endpoint).details.technology.should eq "cs_carter"
  end
end
