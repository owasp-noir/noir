require "../../func_spec.cr"

# `stage: ${opt:stage, 'dev'}` deploys to `dev`; `${sls:stage}` has no
# literal fallback, so no stage segment. `functions` as a list with a
# `${file()}` item, and as a whole-value `${file():key}`.
expected_endpoints = [
  Endpoint.new("/dev/orders", "GET"),
  Endpoint.new("/dev/health", "GET"),
  Endpoint.new("/users", "GET"),
]

FunctionalTester.new("fixtures/specification/serverless_framework_variables/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
