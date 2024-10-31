require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/customer", "POST"),
]

FunctionalTester.new("fixtures/rust/rocket/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).test_all
