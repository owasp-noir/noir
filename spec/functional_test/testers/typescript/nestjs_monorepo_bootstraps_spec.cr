require "../../func_spec.cr"

# One package.json, three apps. apps/api bootstraps with a global prefix
# (excluding `health`, matched without the version) and a `defaultVersion`
# read from a constant; apps/worker bootstraps on its own, so neither
# setting reaches it; apps/admin is an Nx application (`project.json`), so
# neither reaches it either.
expected_endpoints = [
  Endpoint.new("/v1/health", "GET"),
  Endpoint.new("/api/v1/items", "GET"),
  Endpoint.new("/jobs", "GET"),
  Endpoint.new("/users", "GET"),
]

FunctionalTester.new("fixtures/typescript/nestjs_monorepo_bootstraps/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
