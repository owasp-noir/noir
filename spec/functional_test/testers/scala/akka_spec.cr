require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/users/{userId}", "GET", [
    Param.new("userId", "", "path"),
    Param.new("filter", "", "query"),
  ]),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST", [Param.new("body", "User", "json")]),
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/v1/items", "GET", [
    Param.new("category", "", "query"),
    Param.new("sort", "", "query"),
  ]),
  Endpoint.new("/api/v1/items/{itemId}", "GET", [Param.new("itemId", "", "path")]),
  Endpoint.new("/api/v1/items/{itemId}", "PUT", [
    Param.new("itemId", "", "path"),
    Param.new("body", "Item", "json"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/api/v1/items/{itemId}", "DELETE", [
    Param.new("itemId", "", "path"),
    Param.new("X-API-Key", "", "header"),
  ]),
  Endpoint.new("/search", "POST", [Param.new("q", "", "query")]),
  Endpoint.new("/orders", "GET"),
  Endpoint.new("/orders", "POST", [Param.new("body", "Item", "json")]),
  Endpoint.new("/orders/{orderId}", "DELETE", [Param.new("orderId", "", "path")]),
  Endpoint.new("/orders/{orderId}/price", "GET", [
    Param.new("orderId", "", "path"),
    Param.new("currency", "", "query"),
  ]),
  # Leaf method directly under a pathPrefix with no inner path()/pathEnd.
  Endpoint.new("/ip/{ip}", "GET", [Param.new("ip", "", "path")]),
  Endpoint.new("/ip", "POST", [Param.new("body", "Item", "json")]),
  # `pathEnd*` redundant inside path()/on a path() line must not emit a
  # prefix-only route (no bare `/things` GET / or `/widgets` GET).
  Endpoint.new("/things", "GET"),
  Endpoint.new("/widgets/{widgetId}", "GET", [Param.new("widgetId", "", "path")]),
]

FunctionalTester.new("fixtures/scala/akka/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
