require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/upload", "POST"),
]

FunctionalTester.new("fixtures/js_express/", {
  :techs     => 1,
  :endpoints => 2,
}, extected_endpoints).test_all
