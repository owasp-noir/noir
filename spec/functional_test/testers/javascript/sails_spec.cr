require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/:id", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/profile", "GET", [
    Param.new("section", "", "query"),
    Param.new("x-profile-token", "", "header"),
  ]),
  Endpoint.new("/login", "POST", [
    Param.new("username", "", "json"),
    Param.new("password", "", "json"),
    Param.new("sessionId", "", "cookie"),
  ]),
  Endpoint.new("/about", "GET"),
  # Method-less address -- matches every HTTP verb.
  Endpoint.new("/webhook", "GET"),
  Endpoint.new("/webhook", "POST"),
  Endpoint.new("/webhook", "PUT"),
  Endpoint.new("/webhook", "DELETE"),
  Endpoint.new("/webhook", "PATCH"),
  Endpoint.new("/webhook", "HEAD"),
  Endpoint.new("/webhook", "OPTIONS"),
  # Note: the `r|^/\d+/(\w+)/(\w+)$|foo,bar` regex-address entry in the
  # fixture is intentionally not modeled and must not appear above.
]

FunctionalTester.new("fixtures/javascript/sails/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
