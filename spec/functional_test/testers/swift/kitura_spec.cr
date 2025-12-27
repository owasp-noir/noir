require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/:userID", "GET"),
  Endpoint.new("/users/:userID/posts/:postID", "PUT"),
  Endpoint.new("/search", "GET"),
  Endpoint.new("/api/login", "POST"),
  Endpoint.new("/profile", "GET"),
  Endpoint.new("/users/:id", "DELETE"),
  Endpoint.new("/articles/:articleID", "PATCH"),
  Endpoint.new("/status", "GET"),
]

FunctionalTester.new("fixtures/swift/kitura/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
