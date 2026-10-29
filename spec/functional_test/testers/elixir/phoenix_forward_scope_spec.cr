require "../../func_spec.cr"

# External `forward` is every method at the prefix and below. `get "/"` inside
# a non-root scope is the scope path, not the scope path plus a slash.
FunctionalTester.new("fixtures/elixir/phoenix_forward_scope/", {
  :techs     => 1,
  :endpoints => 4,
}, [
  Endpoint.new("/api/v1/sites", "GET"),
  Endpoint.new("/api/v1/sites", "POST"),
  Endpoint.new("/api/v1/sites/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/sent-emails{/*path}", "ANY"),
]).perform_tests
