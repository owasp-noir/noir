require "../../func_spec.cr"

# Salvo nested-router prefix composition through `.push(...)`, bare-root
# verbs (`Router::new().get(h)` -> `/`), `.path()`-method chains, and a
# regex-constrained raw-string param (`r"delete/{id|...}"` -> `{id}`).
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/api/todos", "GET"),
  Endpoint.new("/api/todos", "POST"),
  Endpoint.new("/api/todos/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/user/delete/{id}", "POST", [
    Param.new("id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/rust/salvo_nested/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_salvo"),
}).perform_tests
