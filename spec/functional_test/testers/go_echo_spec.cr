require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET", [
    Param.new("abcd_token", "", "cookie"),
  ]),
  Endpoint.new("/pet", "GET", [
    Param.new("query", "", "query"),
    Param.new("X-API-Key", "", "header"),
  ]),
  Endpoint.new("/pet", "POST", [
    Param.new("name", "", "json"),
  ]),
  Endpoint.new("/pet_form", "POST", [
    Param.new("name", "", "form"),
  ]),
  Endpoint.new("/public/secret.html", "GET"),
  Endpoint.new("/public/mob.txt", "GET"),
  Endpoint.new("/public/coffee.txt", "GET"),
  Endpoint.new("/admin/users", "GET"),
  Endpoint.new("/admin/v1/migration", "GET"),
]

FunctionalTester.new("fixtures/go_echo/", {
  :techs     => 1,
  :endpoints => 9,
}, extected_endpoints).test_all
