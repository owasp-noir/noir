require "../../func_spec.cr"

# JAX-RS resources written in Kotlin (#2856): `@ApplicationPath` on a
# Kotlin `Application`, a class `@Path` from a `const val`, Kotlin
# parameter annotations, a data-class entity resolved across files, a
# same-file sub-resource locator and a `@ServerEndpoint` socket.
chat = Endpoint.new("/chat/{room}", "GET", [Param.new("room", "", "path")])
chat.protocol = "ws"

expected_endpoints = [
  chat,
  Endpoint.new("/api/users", "GET", [
    Param.new("page", "1", "query"),
    Param.new("X-Tenant", "", "header"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("service.list", line: 33))
  end,
  Endpoint.new("/api/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/api/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
    Param.new("age", "0", "json"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("service.save", line: 42))
  end,
  Endpoint.new("/api/users/{id}/avatar", "PUT", [
    Param.new("id", "", "path"),
    Param.new("url", "", "form"),
  ]),
  Endpoint.new("/api/users/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/users/{id}/orders", "GET", [
    Param.new("id", "", "path"),
    Param.new("status", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/java/jaxrs_kotlin/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
