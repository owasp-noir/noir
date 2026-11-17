require "../../func_spec.cr"

# A bounded look-ahead that ends inside a multi-byte character is invalid
# UTF-8, and matching a regex against it raises. The parameter scan took
# such a slice after `({ ... })` and after `const { ... }`, and the error
# cost the file every route.
expected_endpoints = [
  Endpoint.new("/login", "POST", [Param.new("id", "", "json")]),
  Endpoint.new("/signup", "POST", [Param.new("email", "", "json")]),
  Endpoint.new("/health", "GET"),
]

FunctionalTester.new("fixtures/javascript/express_multibyte_lookahead/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
