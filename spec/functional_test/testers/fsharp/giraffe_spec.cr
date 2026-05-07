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

FunctionalTester.new("fixtures/fsharp/giraffe/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
