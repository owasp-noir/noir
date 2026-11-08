require "../../func_spec.cr"

# FastMCP `custom_route`s on a module-level server (server.py), a server built
# in a factory function (factory.py), the official MCP SDK's FastMCP
# (sdk_server.py) and an aliased import (alias.py). scopes.py resolves the
# receiver by Python's scope rules: a local or a parameter that shadows a
# server, or a name bound only in a docstring, is not a server. decoy.py
# calls `custom_route` on another object. Neither decoy yields a route. The
# fixtures also import Starlette, which is detected (2 techs) but reports
# none of these routes.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/items/{item_id}", "GET", [
    Param.new("item_id", "", "path"),
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/items/{item_id}", "DELETE", [
    Param.new("item_id", "", "path"),
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/users/{user_id}", "GET", [
    Param.new("user_id", "", "path"),
    Param.new("x-trace-id", "", "header"),
  ]),
  Endpoint.new("/webhook", "POST", [
    Param.new("body", "", "json"),
    Param.new("event", "", "json"),
  ]),
  Endpoint.new("/ready", "GET"),
  Endpoint.new("/status", "GET"),
  Endpoint.new("/alias", "GET"),
  Endpoint.new("/spaced", "GET"),
  Endpoint.new("/local", "POST"),
]

FunctionalTester.new("fixtures/python/fastmcp/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
