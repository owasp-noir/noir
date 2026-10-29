require "../../func_spec.cr"

# `c.Bind(req)` with `req` already a pointer, and a bind method on the
# request type (`req.bind(c)` calling `c.Bind(r)`), both read the request
# struct's tagged fields.
expected_endpoints = [
  Endpoint.new("/login", "POST", [Param.new("user", "", "json")]),
  Endpoint.new("/direct", "POST", [Param.new("user", "", "json")]),
]

FunctionalTester.new("fixtures/go/echo_bind_request_method/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
