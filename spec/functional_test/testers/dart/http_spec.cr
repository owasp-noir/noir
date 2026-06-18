require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/health", "GET", [
    Param.new("name", "", "query"),
    Param.new("X-Trace-Id", "", "header"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/profiles", "PATCH", [
    Param.new("X-Profile-Mode", "", "header"),
  ]),
  Endpoint.new("/files", "GET"),
  Endpoint.new("/reports", "DELETE"),
  Endpoint.new("/uploads", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/switch-users", "PUT"),
  Endpoint.new("/status", "GET"),
]

tester = FunctionalTester.new("fixtures/dart/http/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "does not leak pre-route body reads into previous endpoints" do
  reports = tester.app.endpoints.find { |found| found.url == "/reports" && found.method == "DELETE" }
  reports.should_not be_nil
  reports.try do |endpoint|
    endpoint.params.any? { |param| param.name == "body" && param.param_type == "json" }.should be_false
  end

  uploads = tester.app.endpoints.find { |found| found.url == "/uploads" && found.method == "POST" }
  uploads.should_not be_nil
  uploads.try do |endpoint|
    endpoint.params.any? { |param| param.name == "body" && param.param_type == "json" }.should be_true
  end
end
