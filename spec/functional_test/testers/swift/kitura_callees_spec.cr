require "../../func_spec.cr"

create_endpoint = Endpoint.new("/users/:id", "POST")
create_endpoint.push_param(Param.new("id", "", "path"))
create_endpoint.push_param(Param.new("body", "", "json"))
create_endpoint.push_callee(Callee.new("UserService.build", line: 8))
create_endpoint.push_callee(Callee.new("AuditLog.write", line: 9))
create_endpoint.push_callee(Callee.new("response.send", line: 10))
create_endpoint.push_callee(Callee.new("ResponseBuilder.created", line: 10))
create_endpoint.push_callee(Callee.new("next", line: 11))

search_endpoint = Endpoint.new("/search", "GET")
search_endpoint.push_param(Param.new("q", "", "query"))
search_endpoint.push_callee(Callee.new("SearchMetrics.record", line: 20))
search_endpoint.push_callee(Callee.new("response.send", line: 21))
search_endpoint.push_callee(Callee.new("SearchService.render", line: 21))
search_endpoint.push_callee(Callee.new("next", line: 22))

health_endpoint = Endpoint.new("/health", "GET")
health_endpoint.push_callee(Callee.new("HealthService.check", line: 25))

delayed_endpoint = Endpoint.new("/delayed", "GET")
delayed_endpoint.push_callee(Callee.new("DelayService.wait", line: 29))

profile_endpoint = Endpoint.new("/profile", "GET")
profile_endpoint.push_callee(Callee.new("ProfileService.load", line: 41))
profile_endpoint.push_callee(Callee.new("response.send", line: 42))
profile_endpoint.push_callee(Callee.new("ProfilePresenter.render", line: 42))
profile_endpoint.push_callee(Callee.new("next", line: 43))

expected_endpoints = [
  create_endpoint,
  search_endpoint,
  health_endpoint,
  delayed_endpoint,
  profile_endpoint,
]

FunctionalTester.new("fixtures/swift/kitura_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
