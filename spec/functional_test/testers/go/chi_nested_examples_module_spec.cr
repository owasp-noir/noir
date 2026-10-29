require "../../func_spec.cr"

# `_examples/rest` is its own module (it has a go.mod), so Go builds it as an
# ordinary package and its routes count even when the scan starts at the
# parent module. `_examples/shared` belongs to the parent module and stays
# excluded.
expected_endpoints = [
  Endpoint.new("/ping", "GET"),
]

FunctionalTester.new("fixtures/go/chi_nested_examples_module/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
