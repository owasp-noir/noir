require "../../func_spec.cr"

# `mix format` parenthesises route macros (`get("/health") do`,
# `get("/ping", do: ...)`, `match("/hook", via: [...])`). Only a module that
# `use Plug.Router`s is read that way: `get("/api/users")` in lib/client.ex
# is an HTTP call, not a route.
expected_endpoints = [
  Endpoint.new("/plain", "GET"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/items", "POST", [Param.new("name", "", "form")]),
  Endpoint.new("/ping", "GET"),
  Endpoint.new("/items/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/hook", "POST"),
  Endpoint.new("/hook", "PUT"),
  Endpoint.new("/admin/users", "GET"),
]

FunctionalTester.new("fixtures/elixir/plug_paren_macros/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
