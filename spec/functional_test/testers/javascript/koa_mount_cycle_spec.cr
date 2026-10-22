require "../../func_spec.cr"

# Mount-prefix propagation appended to the list it was iterating, so a
# self-mount never finished and an a -> b -> a cycle doubled its prefixes
# every pass (the scan hung). Each router is now expanded at most once per
# mount path.
expected_endpoints = [
  Endpoint.new("/r/a", "GET"),
  Endpoint.new("/r/x/b", "GET"),
  Endpoint.new("/r/z/b", "GET"),
  Endpoint.new("/v1/health", "GET"),
]

FunctionalTester.new("fixtures/javascript/koa_mount_cycle/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
