require "../../func_spec.cr"

# Routes without an explicit method filter fall back to GET/POST/PUT/DELETE/PATCH.
fallback_methods = ["GET", "POST", "PUT", "DELETE", "PATCH"]

expected_endpoints = [] of Endpoint

# `route "/" >=> text "home"` — no method filter on the line.
fallback_methods.each { |m| expected_endpoints << Endpoint.new("/", m) }

# Verb-prefixed simple routes covering all major HTTP methods.
expected_endpoints << Endpoint.new("/users", "GET")
expected_endpoints << Endpoint.new("/login", "POST")
expected_endpoints << Endpoint.new("/profile", "PUT")
expected_endpoints << Endpoint.new("/items", "DELETE")
expected_endpoints << Endpoint.new("/notes", "PATCH")

# `routef` typed parameters — no method filter, so fallback verbs.
fallback_methods.each do |m|
  expected_endpoints << Endpoint.new("/users/:int", m, [Param.new("int", "int", "path")])
end
fallback_methods.each do |m|
  expected_endpoints << Endpoint.new("/items/:int/notes/:string", m, [
    Param.new("int", "int", "path"),
    Param.new("string", "string", "path"),
  ])
end
fallback_methods.each do |m|
  expected_endpoints << Endpoint.new("/big/:int64", m, [Param.new("int64", "int64", "path")])
end
fallback_methods.each do |m|
  expected_endpoints << Endpoint.new("/flag/:bool", m, [Param.new("bool", "bool", "path")])
end

# subRoute "/api" prefix applied to nested routes.
expected_endpoints << Endpoint.new("/api/health", "GET")
expected_endpoints << Endpoint.new("/api/version", "GET")
# Nested subRoute "/v2" inside "/api".
expected_endpoints << Endpoint.new("/api/v2/echo", "POST")

# subRoutef "/users/%i" propagates a typed path param to nested routes.
expected_endpoints << Endpoint.new("/users/:int/profile", "GET", [
  Param.new("int", "int", "path"),
])

# Method filter on the preceding line, joined via leading `>=>`.
expected_endpoints << Endpoint.new("/multiline", "GET")

# routex (regex) reported verbatim.
expected_endpoints << Endpoint.new("/foo(/?)", "GET")

# routeCi without explicit method filter.
fallback_methods.each { |m| expected_endpoints << Endpoint.new("/case", m) }

# Giraffe Endpoint Routing — `GET [...]` wraps routes that inherit the verb.
expected_endpoints << Endpoint.new("/ping", "GET")
expected_endpoints << Endpoint.new("/status", "GET")
expected_endpoints << Endpoint.new("/submit", "POST")
# `subRoute "/admin" [...]` with bracket-style children.
expected_endpoints << Endpoint.new("/admin/dashboard", "GET")
expected_endpoints << Endpoint.new("/admin/sessions/:int", "DELETE", [
  Param.new("int", "int", "path"),
])

# --- Api.fs ---------------------------------------------------------------
# `VERB >=> choose [...]` — verb scopes the whole block, so each nested
# route reports only that method (no fallback-method explosion).
expected_endpoints << Endpoint.new("/products", "GET")
# `route Urls.home` resolves against the `let home = "/home"` binding.
expected_endpoints << Endpoint.new("/home", "GET")
# `routef "/products/%i"` typed param, scoped to GET.
expected_endpoints << Endpoint.new("/products/:int", "GET", [Param.new("int", "int", "path")])
# `routeCif "/search/%s"` — case-insensitive typed route.
expected_endpoints << Endpoint.new("/search/:string", "GET", [Param.new("string", "string", "path")])
# `routeCix "/legacy(/?)"` — case-insensitive regex route, verbatim path.
expected_endpoints << Endpoint.new("/legacy(/?)", "GET")
# Inline `POST >=> choose [...]`.
expected_endpoints << Endpoint.new("/products", "POST")
# `routeBind<Customer> "/customers/{customerId}/orders/{orderId}"` — named
# params become `:customerId` / `:orderId` string path params.
expected_endpoints << Endpoint.new("/customers/:customerId/orders/:orderId", "POST", [
  Param.new("customerId", "string", "path"),
  Param.new("orderId", "string", "path"),
])

FunctionalTester.new("fixtures/fsharp/giraffe/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
