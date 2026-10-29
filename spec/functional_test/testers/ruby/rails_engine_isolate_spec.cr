require "../../func_spec.cr"

# #3318: `isolate_namespace Shop` puts the engine's controllers under
# `app/controllers/shop/`, so `resources` rows and `to:` handlers resolve there.
expected_endpoints = [
  Endpoint.new("/api/v3/products", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/api/v3/products/:id", "GET"),
  Endpoint.new("/api/v3/auth/login", "POST", [Param.new("email", "", "json")]),
]

FunctionalTester.new("fixtures/ruby/rails_engine_isolate/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
