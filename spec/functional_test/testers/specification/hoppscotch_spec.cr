require "../../func_spec.cr"

expected_endpoints = [
  # my-api.json — the issue #2912 example.
  Endpoint.new("/users/1", "GET", [
    Param.new("q", "x", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("name", "a", "json"),
  ]),
  # shop-collection.json — nested folders, inherited auth/headers and
  # `<<shopUrl>>` resolved from environment.json. not-hoppscotch.json lacks
  # `v`/`folders` and must contribute nothing.
  Endpoint.new("/v2/orders/:orderId", "GET", [
    Param.new("expand", "items", "query"),
    Param.new("orderId", "", "path"),
    Param.new("X-Tenant", "acme", "header"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/v2/orders/search", "POST", [
    Param.new("X-Api-Key", "", "header"),
    Param.new("status", "open", "form"),
    Param.new("sort", "date", "form"),
  ]),
  # A child folder's header overrides the parent's (`acme` would fail the
  # value check). Its inactive auth block suppresses the inherited bearer.
  Endpoint.new("/v2/catalog", "GET", [
    Param.new("X-Tenant", "public", "header"),
  ]),
  Endpoint.new("/v2/orders/receipt", "PUT", [
    Param.new("file", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/specification/hoppscotch/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
