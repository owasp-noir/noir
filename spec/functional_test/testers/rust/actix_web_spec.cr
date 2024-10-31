require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/echo", "POST"),
]

FunctionalTester.new("fixtures/rust/actix_web/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).test_all
