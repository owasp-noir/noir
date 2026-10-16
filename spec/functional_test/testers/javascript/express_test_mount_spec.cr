require "../../func_spec.cr"

# Production mounts the users router at `/api/v1/users` only. The test apps
# mount it at `/test-prefix` (test/users.test.js) and `/integration-prefix`
# (test/users.integration.js, a describe suite with a plain name); those
# prefixes exist only in-process and must not multiply the route.
FunctionalTester.new("fixtures/javascript/express_test_mount/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("/api/v1/users/list", "GET"),
]).perform_tests
