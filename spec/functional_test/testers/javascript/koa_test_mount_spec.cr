require "../../func_spec.cr"

# `new Router({ prefix: '/koa-test-prefix' })` mounting the router in
# test/items.test.js is an in-process test app, not a production mount.
FunctionalTester.new("fixtures/javascript/koa_test_mount/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("/api/items", "GET"),
]).perform_tests
