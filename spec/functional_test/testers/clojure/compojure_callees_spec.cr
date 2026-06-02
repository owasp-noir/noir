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

vars_endpoint = Endpoint.new("/vars", "GET")
vars_endpoint.push_callee(Callee.new("wrap", line: 31))
vars_endpoint.push_callee(Callee.new("handlers/show-vars", line: 31))

# Operators (`/`, `+`) are filtered; only the real service call surfaces.
calc_endpoint = Endpoint.new("/calc", "GET")
calc_endpoint.push_callee(Callee.new("response/ok", line: 36))
calc_endpoint.push_callee(Callee.new("math.util/scale", line: 36))

# compojure.api.resource: each method's `:handler` body yields its callees.
items_get_endpoint = Endpoint.new("/items", "GET")
items_get_endpoint.push_callee(Callee.new("item.service/list-all", line: 41))

items_post_endpoint = Endpoint.new("/items", "POST")
items_post_endpoint.push_callee(Callee.new("item.service/create!", line: 42))

expected_endpoints = [
  show_endpoint,
  create_endpoint,
  delete_endpoint,
  quoted_endpoint,
  vars_endpoint,
  calc_endpoint,
  items_get_endpoint,
  items_post_endpoint,
]

FunctionalTester.new("fixtures/clojure/compojure_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
