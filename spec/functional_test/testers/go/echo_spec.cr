require "../../func_spec.cr"

expected_endpoints = [
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
  Endpoint.new("/mixed-get", "GET"),
  Endpoint.new("/mixed-post", "POST", [
    Param.new("field1", "", "form"),
  ]),
  Endpoint.new("/mixed-put", "PUT"),
  Endpoint.new("/mixed-delete", "DELETE"),
  Endpoint.new("/multiline", "GET", [
    Param.new("ml_param", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/go/echo/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
