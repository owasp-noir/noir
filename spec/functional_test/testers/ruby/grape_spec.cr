require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/users/{id}", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/orders", "GET"),
  Endpoint.new("/orders", "POST"),
  Endpoint.new("/accounts/{account_id}/profile", "GET", [
    Param.new("account_id", "", "path"),
    Param.new("expand", "", "query"),
  ]),
  # `requires :title` -> json (NOT duplicated as query by the later
  # `params[:title]` read); `headers["X-Request-Id"]` literal -> header;
  # the bare-variable `headers[token_header]` subscript is NOT captured.
  Endpoint.new("/articles", "POST", [
    Param.new("title", "", "json"),
    Param.new("X-Request-Id", "", "header"),
  ]),
  Endpoint.new("/v2/status", "GET"),
  # Symbol verb path (`get :ping`) is a literal segment, not a `{ping}` param.
  Endpoint.new("/v2/status/ping", "GET"),
]

FunctionalTester.new("fixtures/ruby/grape/", {
  :techs     => 1,
  :endpoints => 13,
}, expected_endpoints).perform_tests
