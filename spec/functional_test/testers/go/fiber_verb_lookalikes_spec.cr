require "../../func_spec.cr"

# Regression: `env.Get(key, default)`, `store.Put(key, value)`,
# `mlog.Any(key, value)` and `cache.Get(key, &out)` share a verb name with
# the router API and used to be decoded as routes.
expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST"),
]

FunctionalTester.new("fixtures/go/fiber_verb_lookalikes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
