require "../../func_spec.cr"

list_endpoint = Endpoint.new("/users", "GET")
list_endpoint.push_callee(Callee.new("response/ok"))
list_endpoint.push_callee(Callee.new("user.service/list"))

create_endpoint = Endpoint.new("/users", "POST")
create_endpoint.push_callee(Callee.new("audit.log/write!"))
create_endpoint.push_callee(Callee.new("response/created"))
create_endpoint.push_callee(Callee.new("user.service/create!"))

health_endpoint = Endpoint.new("/health", "GET")
health_endpoint.push_callee(Callee.new("response/ok"))
health_endpoint.push_callee(Callee.new("health.service/check"))

inline_endpoint = Endpoint.new("/api/inline", "GET")
inline_endpoint.push_callee(Callee.new("response/ok"))
inline_endpoint.push_callee(Callee.new("inline.service/run"))

# Syntax-quoted handler in a conj-built interceptor vector.
dashboard_endpoint = Endpoint.new("/dashboard", "GET")
dashboard_endpoint.push_callee(Callee.new("dashboard-page"))

expected_endpoints = [
  list_endpoint,
  create_endpoint,
  health_endpoint,
  inline_endpoint,
  dashboard_endpoint,
]

FunctionalTester.new("fixtures/clojure/pedestal_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
