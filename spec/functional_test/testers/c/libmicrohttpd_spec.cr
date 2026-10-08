require "../../func_spec.cr"

expected_endpoints = [
  # `#define`d URL, method in the same condition (past a `;` in a string).
  Endpoint.new("/login", "POST", [Param.new("user", "", "form")]),
  # Method from a guard in the branch; params from the helper it calls.
  Endpoint.new("/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("Accept-Language", "", "header"),
  ]),
  Endpoint.new("/session", "GET", [Param.new("sid", "", "cookie")]),
  # `strncmp` is a prefix match.
  Endpoint.new("/static/*", "GET"),
  # A handler that never compares the URL serves every path.
  Endpoint.new("/", "GET", [Param.new("name", "", "query")]),
]

FunctionalTester.new("fixtures/c/libmicrohttpd/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
