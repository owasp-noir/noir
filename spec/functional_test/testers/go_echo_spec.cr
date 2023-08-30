require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/pet", "GET", [
    Param.new("query", "", "query"),
  ]),
  Endpoint.new("/pet", "POST", [
    Param.new("name", "", "json"),
  ]),
  Endpoint.new("/pet_form", "POST", [
    Param.new("name", "", "form"),
  ]),
  Endpoint.new("/public/secret.html", "GET"),
]

FunctionalTester.new("fixtures/go_echo/", {
  :techs     => 1,
  :endpoints => 5,
}, extected_endpoints).test_all
