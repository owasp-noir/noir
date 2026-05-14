require "../../func_spec.cr"

def dart_frog_endpoint_with_callees(url, method, params = [] of Param, callees = [] of Callee)
  endpoint = Endpoint.new(url, method, params)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

user_callees = [
  Callee.new("context.read", line: 4),
  Callee.new("service.find", line: 7),
  Callee.new("AuditLog.write", line: 8),
  Callee.new("Response.json", line: 9),
  Callee.new("serializeUser", line: 9),
  Callee.new("context.request.json", line: 11),
  Callee.new("service.save", line: 12),
  Callee.new("UserDto.fromJson", line: 12),
  Callee.new("renderUser", line: 13),
  Callee.new("Response", line: 15),
]

status_callees = [
  Callee.new("Response.json", line: 4),
  Callee.new("HealthService.status", line: 4),
]

expected_endpoints = [
  dart_frog_endpoint_with_callees("/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ], user_callees),
  dart_frog_endpoint_with_callees("/users/{id}", "PUT", [
    Param.new("id", "", "path"),
  ], user_callees),
  dart_frog_endpoint_with_callees("/status", "GET", [] of Param, status_callees),
  dart_frog_endpoint_with_callees("/status", "POST", [] of Param, status_callees),
  dart_frog_endpoint_with_callees("/status", "PUT", [] of Param, status_callees),
  dart_frog_endpoint_with_callees("/status", "DELETE", [] of Param, status_callees),
  dart_frog_endpoint_with_callees("/status", "PATCH", [] of Param, status_callees),
]

tester = FunctionalTester.new("fixtures/dart/dart_frog_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

it "reports the exact Dart Frog callee list for method-routed files" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/users/{id}" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(user_callees.map { |callee| {callee.name, callee.line} })
  end
end
