require "../../func_spec.cr"

chat_ws_endpoint = Endpoint.new("/ws/chat/{roomId}/{username}", "GET", [
  Param.new("roomId", "", "path"),
  Param.new("username", "", "path"),
])
chat_ws_endpoint.protocol = "ws"

expected_endpoints = [
  Endpoint.new("/services/users", "GET", [
    Param.new("page", "0", "query"),
    Param.new("size", "", "query"),
  ]),
  Endpoint.new("/services/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("X-Trace", "", "header"),
  ]),
  Endpoint.new("/services/users", "POST", [
    Param.new("username", "", "json"),
    Param.new("email", "", "json"),
    Param.new("age", "", "json"),
  ]),
  Endpoint.new("/services/users/login", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
  ]),
  Endpoint.new("/services/users/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("username", "", "json"),
    Param.new("email", "", "json"),
    Param.new("age", "", "json"),
  ]),
  Endpoint.new("/services/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/services/users/{id}", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("active", "false", "query"),
    Param.new("role", "", "query"),
    Param.new("X-Tenant", "", "header"),
    Param.new("sort", "created", "query"),
  ]),
  Endpoint.new("/services/users/{id}/profile", "GET", [
    Param.new("id", "", "path"),
    Param.new("include", "", "query"),
  ]),
  Endpoint.new("/services/users/{id}/profile/settings", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/services/api/constant/search", "GET", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/services/api/catalog/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("view", "", "query"),
  ]),
  Endpoint.new("/services/api/catalog", "POST", [
    Param.new("title", "", "json"),
    Param.new("count", "", "json"),
  ]),
  Endpoint.new("/legacy/ping", "GET"),
  Endpoint.new("/simple-api/simple", "GET"),
  chat_ws_endpoint,
]

FunctionalTester.new("fixtures/java/jaxrs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
