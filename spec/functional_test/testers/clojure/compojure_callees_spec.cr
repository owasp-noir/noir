require "../../func_spec.cr"

show_endpoint = Endpoint.new("/users/:id", "GET", [
  Param.new("id", "", "path"),
])
show_endpoint.push_callee(Callee.new("user.service/find-user", line: 7))
show_endpoint.push_callee(Callee.new("audit.log/write!", line: 8))
show_endpoint.push_callee(Callee.new("response/ok", line: 9))
show_endpoint.push_callee(Callee.new("present-user", line: 9))

create_endpoint = Endpoint.new("/users", "POST")
create_endpoint.push_callee(Callee.new("payload/from-request", line: 12))
create_endpoint.push_callee(Callee.new("user.service/create!", line: 13))
create_endpoint.push_callee(Callee.new("response/created", line: 14))
create_endpoint.push_callee(Callee.new("present-user", line: 14))

delete_endpoint = Endpoint.new("/api/users/:id", "DELETE", [
  Param.new("id", "", "path"),
  Param.new("force", "", "query"),
])
delete_endpoint.push_callee(Callee.new("audit.log/write!", line: 18))
delete_endpoint.push_callee(Callee.new("response/ok", line: 19))
delete_endpoint.push_callee(Callee.new("user.service/delete!", line: 19))

quoted_endpoint = Endpoint.new("/quoted", "GET")
quoted_endpoint.push_callee(Callee.new("response/ok", line: 26))
quoted_endpoint.push_callee(Callee.new("safe.service/run!", line: 26))

expected_endpoints = [
  show_endpoint,
  create_endpoint,
  delete_endpoint,
  quoted_endpoint,
]

FunctionalTester.new("fixtures/clojure/compojure_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
