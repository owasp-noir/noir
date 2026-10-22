require "../../func_spec.cr"

# `@Controller()` + `@Get()` is the app root. Joining the two empty paths
# used to produce an empty URL, which the optimizer drops, so the route
# vanished from every output format.
expected_endpoints = [
  Endpoint.new("/", "GET"),
]

FunctionalTester.new("fixtures/typescript/nestjs_root_controller/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
