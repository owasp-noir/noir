require "../../func_spec.cr"

list_endpoint = Endpoint.new("/api/users", "GET")
list_endpoint.push_callee(Callee.new("user.service/list"))
list_endpoint.push_callee(Callee.new("audit.log/write!"))
list_endpoint.push_callee(Callee.new("response/ok"))
list_endpoint.push_callee(Callee.new("present-users"))

create_endpoint = Endpoint.new("/api/users", "POST")
create_endpoint.push_callee(Callee.new("payload/from-request"))
create_endpoint.push_callee(Callee.new("response/created"))
create_endpoint.push_callee(Callee.new("user.service/create!"))

inline_endpoint = Endpoint.new("/api/inline", "GET")
inline_endpoint.push_callee(Callee.new("response/ok"))
inline_endpoint.push_callee(Callee.new("inline.service/run"))

items_endpoint = Endpoint.new("/api/items/:id", "GET", [
  Param.new("id", "", "path"),
])
items_endpoint.push_callee(Callee.new("get-item"))

health_endpoint = Endpoint.new("/api/health", "GET")
health_endpoint.push_callee(Callee.new("health-check"))

expected_endpoints = [
  list_endpoint,
  create_endpoint,
  inline_endpoint,
  items_endpoint,
  health_endpoint,
]

FunctionalTester.new("fixtures/clojure/reitit_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
