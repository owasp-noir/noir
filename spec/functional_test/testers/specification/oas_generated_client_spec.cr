require "../../func_spec.cr"

# The OpenAPI document an SDK was generated from describes a remote API the SDK
# consumes: `.openapi-generator/FILES` lists it beside the client runtime
# (`client.go`, `configuration.go`). A server stub lists its document too, but
# has no client runtime, so its endpoints stay.
expected_endpoints = [
  Endpoint.new("/pets", "GET"),
]

FunctionalTester.new("fixtures/specification/oas_generated_client/", {
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
