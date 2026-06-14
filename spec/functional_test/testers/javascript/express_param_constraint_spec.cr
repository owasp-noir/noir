require "../../func_spec.cr"

# Express param regex constraints (`:id([0-9]+)`) normalize down to the
# bare param. The constraint body must not leak a phantom path param.
expected_endpoints = [
  Endpoint.new("/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/files/:name", "GET", [Param.new("name", "", "path")]),
  Endpoint.new("/items/:pk", "DELETE", [Param.new("pk", "", "path")]),
]

FunctionalTester.new("fixtures/javascript/express_param_constraint/", {
  :techs     => 1,
  :endpoints => 3,
}, expected_endpoints).perform_tests
