require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/foo", "GET"),
  Endpoint.new("/bar", "POST"),
]

FunctionalTester.new("fixtures/rust_axum/", {
  :techs     => 1,
  :endpoints => 3,
}, extected_endpoints).test_all
