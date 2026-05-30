require "../../func_spec.cr"

# Play SIRD / SimpleRouter: routes delegate to a programmatic router class
# (`-> /v1/posts v1.post.PostRouter`) whose routing is a PartialFunction.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/v1/posts/", "GET"),
  Endpoint.new("/v1/posts/", "POST"),
  Endpoint.new("/v1/posts/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/v1/posts/:id", "PUT", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/scala/play_sird/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
