require "../../func_spec.cr"

# Regression test: a mount cycle (`app` mounts `sub`, `sub` mounts `app`)
# removed the root prefix from every app, so all of their routes were
# silently dropped. They are now reported unprefixed. A cycle below a real
# root is followed once instead of growing the prefix forever.
expected_endpoints = [
  Endpoint.new("/status", "GET"),
  Endpoint.new("/a/b/deep", "GET"),
]

FunctionalTester.new("fixtures/python/aiohttp_subapp_cycle/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
