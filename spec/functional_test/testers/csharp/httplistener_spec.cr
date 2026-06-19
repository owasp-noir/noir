require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/health", "GET", [
    Param.new("X-Trace-Id", "", "header"),
  ]),
  Endpoint.new("/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("Content-Type", "", "header"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/users/delete", "DELETE", [
    Param.new("sid", "", "cookie"),
  ]),
  Endpoint.new("/ready", "GET"),
  Endpoint.new("/status", "HEAD"),
  Endpoint.new("/users", "PUT", [
    Param.new("X-Request-Id", "", "header"),
  ]),
  Endpoint.new("/users/profile", "PATCH", [
    Param.new("include", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/csharp/httplistener/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "C# HttpListener analyzer edge cases" do
  it "marks endpoints with the dedicated technology" do
    health = tester.app.endpoints.find { |e| e.url == "/health" && e.method == "GET" }
    health.should_not be_nil
    health.as(Endpoint).details.technology.should eq "cs_httplistener"
  end

  it "does not emit a default GET for a path switch case that contains method dispatch" do
    tester.app.endpoints.any? { |e| e.url == "/status" && e.method == "GET" }.should be_false
  end
end
