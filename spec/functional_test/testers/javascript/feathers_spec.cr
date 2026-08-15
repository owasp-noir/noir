require "../../func_spec.cr"

expected_endpoints = [
  # /messages — full CRUD, service class resolved across a file
  # boundary (`require('./messages.class')`), the generator's
  # convention.
  Endpoint.new("/messages", "GET", [
    Param.new("author", "", "query"),
  ]),
  Endpoint.new("/messages/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/messages", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/messages/:id", "PUT", [
    Param.new("id", "", "path"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/messages/:id", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/messages/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),

  # /reviews — same-file class implementing only find/get; update/
  # create/patch/remove must NOT be fabricated.
  Endpoint.new("/reviews", "GET", [
    Param.new("rating", "", "query"),
  ]),
  Endpoint.new("/reviews/:id", "GET", [
    Param.new("id", "", "path"),
    Param.new("x-trace-id", "", "header"),
  ]),

  # /health — inline object literal implementing find + create, but
  # registered with an explicit `{ methods: ['find'] }` option that
  # restricts external exposure to `find` only.
  Endpoint.new("/health", "GET"),

  # /logs — `new LogService()` from an unresolvable external package
  # (`feathers-memory`); the documented full-CRUD fallback applies
  # since `new X(...)` alone is treated as sufficient evidence.
  Endpoint.new("/logs", "GET"),
  Endpoint.new("/logs/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/logs", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/logs/:id", "PUT", [
    Param.new("id", "", "path"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/logs/:id", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/logs/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/javascript/feathers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
