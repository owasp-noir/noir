require "../../func_spec.cr"

# Quart's take on the "large application" layout: main/views.py never
# mentions quart, and its blueprint is registered from inside create_app()
# under an alias.
expected_endpoints = [
  Endpoint.new("/auth/login", "POST"),
  Endpoint.new("/own/", "GET"),
]

FunctionalTester.new("fixtures/python/quart_large_app/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
