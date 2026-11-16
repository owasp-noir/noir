require "../../func_spec.cr"

# `register_blueprint(bp, url_prefix=<expression>)`: a prefix built from a
# string constant (imported by name, read off an imported module, or bound
# in the registering file) with `+` or an f-string is the string it
# evaluates to. `API_PREFIX + "/users"` used to mount the blueprint at the
# root, and `f"{API_PREFIX}/items"` reported `/{API_PREFIX}/items/` with
# `API_PREFIX` as a path parameter.
expected_endpoints = [
  Endpoint.new("/api/v1/users/<int:user_id>", "GET", [Param.new("user_id", "", "path")]),
  Endpoint.new("/api/v1/items/", "POST"),
  Endpoint.new("/api/v1/reports/daily", "GET"),
  Endpoint.new("/admin/stats", "GET"),
]

FunctionalTester.new("fixtures/python/flask_blueprint_prefix_expression/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
