require "../../func_spec.cr"

# A helper taking an `iris.Party` takes the prefix of the party it is
# handed (`registerUsers(v1.Party("/users"))`).
expected_endpoints = [
  Endpoint.new("/api/v1/users/", "GET"),
  Endpoint.new("/api/v1/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/orders", "POST", [Param.new("dry_run", "", "query")]),
]

FunctionalTester.new("fixtures/go/iris_party_builder/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
