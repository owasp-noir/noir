require "../../func_spec.cr"

# Regression: `urlpatterns = [path(.., include(urlpatterns))]` used to make
# the analyzer recurse into its own list until the stack overflowed (exit 10,
# no output). The rebinding now includes the previous binding.
extracted_endpoints = [
  Endpoint.new("/health/", "GET"),
  Endpoint.new("/v1/health/", "GET"),
  Endpoint.new("/loop/ping/pong/", "GET"),
]

FunctionalTester.new("fixtures/python/django_self_include/", {
  :techs     => 1,
  :endpoints => 3,
}, extracted_endpoints).perform_tests
