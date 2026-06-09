require "../../func_spec.cr"

chat_ws_endpoint = Endpoint.new("/socket/chat/{roomId}", "GET", [
  Param.new("roomId", "", "path"),
])
chat_ws_endpoint.protocol = "ws"

portfolio_ws_endpoint = Endpoint.new("/portfolio", "GET")
portfolio_ws_endpoint.protocol = "ws"

chat_send_endpoint = Endpoint.new("/app/chat/send/{roomId}", "SEND", [
  Param.new("roomId", "", "path"),
])
chat_send_endpoint.protocol = "ws"

chat_presence_endpoint = Endpoint.new("/app/chat/presence/{roomId}", "SUBSCRIBE", [
  Param.new("roomId", "", "path"),
])
chat_presence_endpoint.protocol = "ws"

expected_endpoints = [
  # MyRoutingConfiguration.java
  Endpoint.new("/{user}", "GET", [Param.new("user", "", "path")]),
  Endpoint.new("/{user}/metadata", "HEAD", [Param.new("user", "", "path")]),
  Endpoint.new("/{user}/customers", "GET", [Param.new("user", "", "path")]),
  Endpoint.new("/{user}/0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_.~", "GET", [Param.new("user", "", "path")]),
  Endpoint.new("/{user}", "DELETE", [Param.new("user", "", "path")]),
  Endpoint.new("/{user}", "POST", [Param.new("user", "", "path")]),
  Endpoint.new("/{user}", "PUT", [Param.new("user", "", "path")]),
  Endpoint.new("/{user}/options", "OPTIONS", [Param.new("user", "", "path")]),
  # QuoteRouter.java
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/echo", "POST"),
  Endpoint.new("/quotes/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/quotes", "GET"),
  Endpoint.new("/quotes/0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_.~", "GET"),
  # GatewayRouteConfig.java
  Endpoint.new("/gateway/mcp", "POST"),
  Endpoint.new("/gateway/reports/{id}", "GET", [Param.new("id", "", "path")]),
  # WebSocketConfig.java — STOMP handshake endpoints.
  chat_ws_endpoint,
  portfolio_ws_endpoint,
  # ChatMessageController.java — STOMP application destinations.
  chat_send_endpoint,
  chat_presence_endpoint,
  # boot-context application.properties — Spring Boot servlet context path
  Endpoint.new("/portal/context/status", "GET"),
  # ComposedAnnotationController.java
  Endpoint.new("/internal/reports", "GET"),
  Endpoint.new("/internal/submit", "POST"),
  # ExternalComposedAnnotationController.java
  Endpoint.new("/external/audit", "GET"),
  Endpoint.new("/external/reports/{id}", "DELETE", [Param.new("id", "", "path")]),
  # CatalogApi.java + CatalogController.java
  Endpoint.new("/api/catalog/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("view", "", "query"),
  ]),
  Endpoint.new("/api/catalog", "POST", [
    Param.new("title", "", "json"),
    Param.new("count", "", "json"),
  ]),
  # ProductRouter.java — WebMvc.fn `nest(path("/product"), ...)`
  # adds `/product` to every verb call inside the lambda body.
  Endpoint.new("/product/name/{name}", "GET", [Param.new("name", "", "path")]),
  Endpoint.new("/product/id/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/catalog/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/catalog", "POST"),
  # StaticResourceConfig.java — WebMvcConfigurer resource handlers.
  Endpoint.new("/assets/**", "GET"),
  Endpoint.new("/webjars/**", "GET"),
  # ItemController.java
  Endpoint.new("/items/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/items/json/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/items", "POST", [Param.new("id", "", "json"), Param.new("name", "", "json")]),
  Endpoint.new("/items/update/{id}", "PUT", [Param.new("id", "", "path"), Param.new("id", "", "json"), Param.new("name", "", "json")]),
  Endpoint.new("/items/delete/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/items/requestmap/put", "PUT"),
  Endpoint.new("/items/requestmap/delete", "DELETE"),
  Endpoint.new("/items/any-method", "ANY"),
  Endpoint.new("/items/multiple/methods", "GET"),
  Endpoint.new("/items/multiple/methods", "POST"),
  Endpoint.new("/items/multiple/methods2", "GET"),
  Endpoint.new("/items/multiple/methods2", "POST"),
  Endpoint.new("/items/constants", "GET", [
    Param.new("filter", "all", "query"),
    Param.new("X-Client", "", "header"),
    Param.new("session-id", "", "cookie"),
  ]),
  Endpoint.new("/greet", "GET"),
  Endpoint.new("/greet2", "GET", [
    Param.new("myname", "", "query"),
    Param.new("b", "", "query"),
    Param.new("name", "", "query"),
  ]),
  # ItemController2.java
  Endpoint.new("/items2/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/items2/create", "POST", [Param.new("id", "", "json"), Param.new("name", "", "json")]),
  Endpoint.new("/items2/edit/", "PUT", [Param.new("id", "", "json"), Param.new("name", "", "json")]),
  Endpoint.new("/items2/{id}/thePath", "GET", [Param.new("id", "", "path")]),
  # EmptyController.java
  Endpoint.new("/empty", "GET", [Param.new("tenant", "", "query")]),
  Endpoint.new("/empty/filtered", "GET", [
    Param.new("tenant", "", "query"),
    Param.new("mode", "full", "query"),
    Param.new("X-Client", "mobile", "header"),
  ]),
  # MyController.java
  Endpoint.new("/api/v1/test", "GET"),
  # TApiResponses.java
  Endpoint.new("/multi/annotation", "GET"),
  # TRequestHeader.java
  Endpoint.new("/request/header", "GET"),
  # DuplicateParameter.java
  Endpoint.new("/duplicate/parameter/{token}/test", "DELETE", [Param.new("token", "", "path")]),
  # ThrowsMultiException.java
  Endpoint.new("/throws/multi/exception", "GET"),
  # InventoryClient.java
  Endpoint.new("/api/v2/items/{id}/stock", "PATCH", [Param.new("id", "", "path"), Param.new("quantity", "", "json")]),
  Endpoint.new("/api/v2/items", "GET", [Param.new("category", "", "query")]),
  Endpoint.new("/api/v2/items", "POST", [Param.new("id", "", "json"), Param.new("name", "", "json")]),
  Endpoint.new("/api/v2/items/{id}", "DELETE", [Param.new("id", "", "path")]),
  # InventoryHttpClient.java — Spring HTTP Interface client.
  Endpoint.new("/api/v3/items/{id}/availability", "GET", [
    Param.new("id", "", "path"),
    Param.new("region", "", "query"),
  ]),
  Endpoint.new("/api/v3/items/bulk", "POST", [Param.new("tenant", "", "query")]),
  # CrudReportController.java extends AbstractCrudController.java — the
  # abstract base's @GetMapping routes are inherited under the `/crud`
  # prefix, and the base must NOT emit un-prefixed `/list` or `/{id}`.
  Endpoint.new("/crud", "POST"),
  Endpoint.new("/crud/list", "GET"),
  Endpoint.new("/crud/{id}", "GET", [Param.new("id", "", "path")]),
  # plain/ non-standard source layout — interface and composed annotation
  # declarations in sibling package directories still share the same base.
  Endpoint.new("/plain/items", "GET"),
  Endpoint.new("/plain/plain-audit", "GET"),
]

FunctionalTester.new("fixtures/java/spring/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
