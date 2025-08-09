require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/index", "GET"),
  Endpoint.new("/about", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/create_user", "GET"),
  Endpoint.new("/health_check", "GET"),
  Endpoint.new("/dashboard", "GET"),
]

FunctionalTester.new("fixtures/rust/loco/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests