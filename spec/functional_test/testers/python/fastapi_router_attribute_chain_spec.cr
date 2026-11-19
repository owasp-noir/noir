require "../../func_spec.cr"

# `pkg.router` re-exported by `pkg/__init__.py` and a dotted module chain
# keep the prefix they are included under.
expected_endpoints = [
  Endpoint.new("/auth/login", "POST"),
  Endpoint.new("/billing/invoices", "GET"),
  Endpoint.new("/api/v1/users", "GET"),
]

FunctionalTester.new("fixtures/python/fastapi_router_attribute_chain/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
