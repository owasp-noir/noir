require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/customer", "POST"),
]

FunctionalTester.new("fixtures/rust_rocket/", {
  :techs     => 1,
  :endpoints => 2,
}, extected_endpoints).test_all
