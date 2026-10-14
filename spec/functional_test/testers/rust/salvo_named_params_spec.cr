require "../../func_spec.cr"

# Salvo single-field request reads: `req.query::<u32>("page")` and
# `req.form::<String>("name")` name the parameter they read.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/api/users", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/users", "POST", [Param.new("name", "", "form")]),
  Endpoint.new("/api/users/<id>", "GET", [Param.new("id", "", "path"), Param.new("authorization", "", "header")]),
  Endpoint.new("/api/users/<id>", "DELETE", [Param.new("id", "", "path"), Param.new("authorization", "", "header")]),
  Endpoint.new("/files/<**rest>", "GET"),
  Endpoint.new("/posts/<id:num>", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/rust/salvo_named_params/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_salvo"),
}).perform_tests
