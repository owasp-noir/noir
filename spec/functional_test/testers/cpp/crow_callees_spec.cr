require "../../func_spec.cr"

def endpoint_with_callees(url, method, params = [] of Param, callees = [] of Callee)
  endpoint = Endpoint.new(url, method, params)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

expected_endpoints = [
  endpoint_with_callees("/users/{param1}", "GET", [
    Param.new("param1", "", "path"),
  ], [
    Callee.new("UserService::load", line: 8),
    Callee.new("AuditLog::write", line: 9),
    Callee.new("crow::response", line: 10),
    Callee.new("serializeUser", line: 10),
  ]),
  endpoint_with_callees("/users", "POST", [] of Param, [
    Callee.new("parseJson", line: 15),
    Callee.new("service.save", line: 17),
    Callee.new("crow::response", line: 18),
    Callee.new("renderUser", line: 18),
  ]),
  endpoint_with_callees("/users", "PUT", [] of Param, [
    Callee.new("parseJson", line: 15),
    Callee.new("service.save", line: 17),
    Callee.new("crow::response", line: 18),
    Callee.new("renderUser", line: 18),
  ]),
  endpoint_with_callees("/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("X-Token", "", "header"),
  ], [
    Callee.new("request.url_params.get", line: 24),
    Callee.new("request.get_header_value", line: 25),
    Callee.new("FeatureFlags::enabled", line: 28),
    Callee.new("crow::response", line: 29),
    Callee.new("SearchService::run", line: 29),
  ]),
]

FunctionalTester.new("fixtures/cpp/crow_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
