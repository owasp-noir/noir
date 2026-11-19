require "../../func_spec.cr"

# A Grape API mounted from Rails routes (`mount API::Base, at: "/api"`,
# `mount Internal::API => "/internal"`) serves its routes under that path,
# down through the classes it mounts.
expected_endpoints = [
  Endpoint.new("/api/v1/users", "GET"),
  Endpoint.new("/api/v1/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/internal/status", "GET"),
  # Rails side: the routes file itself.
  Endpoint.new("/up", "GET"),
  Endpoint.new("/api", "GET"),
  Endpoint.new("/internal", "GET"),
]

FunctionalTester.new("fixtures/ruby/grape_rails_mount/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
