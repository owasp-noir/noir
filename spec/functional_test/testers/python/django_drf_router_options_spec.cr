require "../../func_spec.cr"

# A DRF router built with `trailing_slash=False` serves its routes without
# the trailing `/`, and a viewset's `http_method_names` limits the verbs
# its ModelViewSet base would otherwise expose.
extracted_endpoints = [
  Endpoint.new("/tags", "GET"),
  Endpoint.new("/tags", "POST"),
  Endpoint.new("/tags/{pk}", "GET", [Param.new("pk", "", "path")]),
]

FunctionalTester.new("fixtures/python/django_drf_router_options/", {
  :techs     => 1,
  :endpoints => extracted_endpoints.size,
}, extracted_endpoints).perform_tests
