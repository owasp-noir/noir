require "../../func_spec.cr"

# Hono attaches its app prefix via `.basePath('/api')`, either chained on
# construction (`const app = new Hono().basePath('/api')`) or on an
# existing instance (`v2.basePath('/v2')`). Routes registered on the
# instance must carry that prefix.
expected_endpoints = [
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users/:id", "POST", [Param.new("id", "", "path")]),
  Endpoint.new("/v2/ping", "GET"),
]

FunctionalTester.new("fixtures/javascript/hono_basepath/", {
  :techs     => 1,
  :endpoints => 3,
}, expected_endpoints).perform_tests
