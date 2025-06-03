require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET", [Param.new("x-api-key", "", "header")]),
  Endpoint.new("/socket", "GET"),
  Endpoint.new("/query", "POST", [
    Param.new("query", "", "form"),
    Param.new("my_auth", "", "cookie"),
  ]),
  Endpoint.new("/token", "GET", [
    Param.new("grant_type", "", "form"),
    Param.new("redirect_url", "", "form"),
    Param.new("client_id", "", "form"),
  ]),
  Endpoint.new("/1.html", "GET"),
  Endpoint.new("/2.html", "GET"),
]

FunctionalTester.new("fixtures/crystal/kemal/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests
