require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/pet", "GET"),
]

FunctionalTester.new("fixtures/go_echo/", {
  :techs     => 1,
  :endpoints => 2,
}, extected_endpoints).test_all
