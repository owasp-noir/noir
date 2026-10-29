require "../../func_spec.cr"

# #3291: a root `@Get()` under `setGlobalPrefix('api')` is `/api`, not `/api/`.
expected_endpoints = [
  Endpoint.new("/api", "GET"),
  Endpoint.new("/api/health", "GET"),
]

FunctionalTester.new("fixtures/javascript/nestjs_root_global_prefix/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
