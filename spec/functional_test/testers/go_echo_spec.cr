require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/pet", "GET"),
  Endpoint.new("/public/secret.html", "GET"),
]

FunctionalTester.new("fixtures/go_echo/", {
  :techs     => 1,
  :endpoints => 3,
}, extected_endpoints).test_all
