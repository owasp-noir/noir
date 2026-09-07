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

  # Blueprint routes for `api/controllers/admin/ReportController.js`. A
  # classic controller keeps its blueprint identity in a subdirectory --
  # `admin/report`, not the literal filename -- so these are the five REST
  # bindings Sails generates, at `/admin/report`.
  Endpoint.new("/admin/report", "GET"),
  Endpoint.new("/admin/report", "POST"),
  Endpoint.new("/admin/report/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/admin/report/:id", "PATCH", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/admin/report/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),

  # `api/controllers/user/find-one.js` is an actions2 action, not a
  # controller: its shadow route is the path below `api/controllers` and it
  # answers every verb.
  Endpoint.new("/user/find-one", "GET"),
  Endpoint.new("/user/find-one", "POST"),
  Endpoint.new("/user/find-one", "PUT"),
  Endpoint.new("/user/find-one", "DELETE"),
  Endpoint.new("/user/find-one", "PATCH"),
  Endpoint.new("/user/find-one", "HEAD"),
  Endpoint.new("/user/find-one", "OPTIONS"),
]

FunctionalTester.new("fixtures/javascript/sails/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
