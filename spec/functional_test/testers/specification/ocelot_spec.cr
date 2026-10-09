require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/posts/{postId}", "GET", [Param.new("postId", "", "path")]),
  Endpoint.new("/posts/{postId}", "PUT", [Param.new("postId", "", "path")]),
  # No `UpstreamHttpMethod` means Ocelot matches every verb.
  Endpoint.new("/health", "ANY"),
  # Aggregates are GET-only.
  Endpoint.new("/feed", "GET"),
]

FunctionalTester.new("fixtures/specification/ocelot/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
