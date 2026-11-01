require "../../func_spec.cr"

# A routes glob loads files only when it names config/routes and its block
# loads them: a listing loop and app/ or lib/ routes dirs add nothing.
expected_endpoints = [
  Endpoint.new("/home", "GET"),
]

FunctionalTester.new("fixtures/ruby/rails_route_loader_unloaded/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
