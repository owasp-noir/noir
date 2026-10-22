require "../../func_spec.cr"

# `app.register(plugin, { prefix: '/fastify-test-prefix' })` in
# test/plugin.test.js is an in-process test app, not a production mount.
FunctionalTester.new("fixtures/javascript/fastify_test_mount/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("/api/items", "GET"),
]).perform_tests
