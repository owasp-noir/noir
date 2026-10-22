require "../../func_spec.cr"

# `router.use("/oak-test-prefix", users.routes())` inside a `Deno.test` in
# test/mount.ts is an in-process test app, not a production mount.
FunctionalTester.new("fixtures/javascript/oak_test_mount/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("/users/list", "GET"),
]).perform_tests
