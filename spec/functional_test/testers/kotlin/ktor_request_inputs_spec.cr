require "../../func_spec.cr"

# Handler inputs read through `getOrFail` / `getAll`, Ktor 3's
# `call.queryParameters`, `call.request.cookies`, a local `val` holding a
# parameters or headers value, and an inline `receiveParameters()[...]`.
expected_endpoints = [
  Endpoint.new("/a-form-getorfail", "POST", [
    Param.new("title", "", "form"),
    Param.new("body", "", "form"),
    Param.new("tags", "", "form"),
  ]),
  Endpoint.new("/b-path-getorfail/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/c-query-variants", "GET", [
    Param.new("plain", "", "query"),
    Param.new("orfail", "", "query"),
    Param.new("all", "", "query"),
    Param.new("ktor3", "", "query"),
    Param.new("getcall", "", "query"),
  ]),
  Endpoint.new("/d-cookie-header", "GET", [
    Param.new("User-Agent", "", "header"),
    Param.new("Authorization", "", "header"),
    Param.new("X-Multi", "", "header"),
    Param.new("sid", "", "cookie"),
  ]),
  Endpoint.new("/e-local-alias", "GET", [
    Param.new("aliased", "", "query"),
    Param.new("X-Aliased", "", "header"),
  ]),
  Endpoint.new("/f-inline-form", "POST", [Param.new("user", "", "form")]),
]

FunctionalTester.new("fixtures/kotlin/ktor_request_inputs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
