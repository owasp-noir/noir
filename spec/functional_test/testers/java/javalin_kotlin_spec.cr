require "../../func_spec.cr"

# Javalin written in Kotlin (#2856): trailing-lambda handlers, method
# references, the `apiBuilder { path { } }` nesting, `crud(...)`, a
# trailing-lambda `staticFiles.add { }` and a per-file `contextPath`.
# `ctx.header(name, value)` / `ctx.cookie(name, value)` are response
# setters, and `defaults.put("X-Cache", "none")` / an `apply { put(...) }`
# are map calls, so none of them may surface. The context app chains
# `.get { }.post { }` fluently and comments its `contextPath` line.
chat = Endpoint.new("/chat/{room}", "GET", [Param.new("room", "", "path")])
chat.protocol = "ws"

expected_endpoints = [
  Endpoint.new("/ctx/status", "GET"),
  Endpoint.new("/ctx/reload", "POST"),
  Endpoint.new("/assets/**", "GET"),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("expand", "", "query"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("UserRepository.find", line: 64))
  end,
  Endpoint.new("/api/users/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/items", "GET"),
  Endpoint.new("/api/items", "POST"),
  Endpoint.new("/api/items/{item-id}", "GET"),
  Endpoint.new("/api/items/{item-id}", "PATCH"),
  Endpoint.new("/api/items/{item-id}", "DELETE"),
  Endpoint.new("/hello", "GET", [
    Param.new("name", "", "query"),
    Param.new("X-Trace", "", "header"),
  ]),
  Endpoint.new("/users", "POST", [Param.new("body", "User", "json")]).tap do |ep|
    ep.push_callee(Callee.new("UserRepository.save", line: 69))
  end,
  Endpoint.new("/users/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("body", "User", "json"),
  ]),
  Endpoint.new("/login", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("AuthService.login", line: 47))
  end,
  Endpoint.new("/sessions", "DELETE", [Param.new("session", "", "cookie")]),
  chat,
]

FunctionalTester.new("fixtures/java/javalin_kotlin/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
