require "../../func_spec.cr"

# `app.client.*`, `app.cache.get`, `app.redis.get` and `app.queues.queue.get`
# are service calls on a member of the registered `app`, not routes, and the
# routes under the package-benchmark `Benchmarks/` directory are not served by
# the app. `app.routes.grouped(...)` stays a router.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/api/status", "GET"),
]

FunctionalTester.new("fixtures/swift/vapor_client_receivers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("swift_vapor"),
}).perform_tests
