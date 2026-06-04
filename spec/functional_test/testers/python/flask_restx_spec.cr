require "../../func_spec.cr"

# flask-restx: a Blueprint carries the url_prefix, an Api is mounted on
# the blueprint, and `add_namespace(ns, "/users")` sets the mount path —
# all in app.py — while the namespace's Resource routes live in
# resources.py. The fully-resolved prefix is `/api/v1` (blueprint) +
# `/users` (add_namespace), and each Resource verb-method is its own
# endpoint.
expected_endpoints = [
  Endpoint.new("/api/v1/users/<int:user_id>", "GET", [Param.new("user_id", "", "path")]),
  Endpoint.new("/api/v1/users/<int:user_id>", "DELETE", [Param.new("user_id", "", "path")]),
  Endpoint.new("/api/v1/users/me", "GET"),
]

FunctionalTester.new("fixtures/python/flask_restx/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
