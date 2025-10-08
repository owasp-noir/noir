require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/echo", "POST"),
  Endpoint.new("/users/{id}", "GET"),
  Endpoint.new("/users/{user_id}/posts/{post_id}", "GET"),
  Endpoint.new("/search", "GET"),
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/login", "POST"),
  Endpoint.new("/protected", "GET"),
  Endpoint.new("/session", "GET"),
  Endpoint.new("/articles/{id}", "PUT"),
]

FunctionalTester.new("fixtures/rust/actix_web/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests
