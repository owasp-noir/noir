require "../../func_spec.cr"

# Prefix composition: base endpoints, val path/param constants, multi-line
# .in() args, modifier-call literals that must not leak, and Endpoint-typed
# generics that must not merge List entries.
expected_endpoints = [
  Endpoint.new("/books/add", "POST", [
    Param.new("body", "Book", "json"),
    Param.new("X-Auth-Token", "String", "header"),
  ]),
  Endpoint.new("/books/list/all", "GET", [
    Param.new("limit", "Option[Int]", "query"),
  ]),
  Endpoint.new("/user/register", "POST", [Param.new("body", "Register_IN", "json")]),
  Endpoint.new("/user", "GET"),
  Endpoint.new("/p1", "GET"),
  Endpoint.new("/p1/p2", "GET"),
]

FunctionalTester.new("fixtures/scala/tapir_compose/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
