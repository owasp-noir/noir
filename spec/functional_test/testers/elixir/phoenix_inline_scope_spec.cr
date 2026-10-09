require "../../func_spec.cr"

# A one-line `scope ..., do: route` has no `end`. Its prefix covers that line
# only — in the router and inside a route macro body alike — and must not
# leak onto the routes after it.
FunctionalTester.new("fixtures/elixir/phoenix_inline_scope/", {
  :techs     => 1,
  :endpoints => 5,
}, [
  Endpoint.new("/admin/inline", "GET"),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/after", "GET"),
  Endpoint.new("/ops/health", "GET"),
  Endpoint.new("/macro-after", "GET"),
]).perform_tests
