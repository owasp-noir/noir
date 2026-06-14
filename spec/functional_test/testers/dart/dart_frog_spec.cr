require "../../func_spec.cr"

expected_endpoints = [
  # Plain `onRequest` with no `HttpMethod.*` references → fall back
  # to the standard verb set (GET / POST / PUT / DELETE / PATCH).
  Endpoint.new("/", "GET"),
  Endpoint.new("/", "POST"),
  Endpoint.new("/", "PUT"),
  Endpoint.new("/", "DELETE"),
  Endpoint.new("/", "PATCH"),
  # `about.dart` only references `HttpMethod.get`.
  Endpoint.new("/about", "GET"),
  # `users/index.dart` switches on get / post.
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST"),
  # `users/[id].dart` references get / put / delete.
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "DELETE", [Param.new("id", "", "path")]),
  # Nested under `[id]`.
  Endpoint.new("/users/{id}/posts", "GET", [Param.new("id", "", "path")]),
  # `api/health.dart` is the catch-all fallback again.
  Endpoint.new("/api/health", "GET"),
  Endpoint.new("/api/health", "POST"),
  Endpoint.new("/api/health", "PUT"),
  Endpoint.new("/api/health", "DELETE"),
  Endpoint.new("/api/health", "PATCH"),
  # `posts/[...slug].dart` — catch-all wildcard collapses to a path param.
  Endpoint.new("/posts/{slug}", "GET", [Param.new("slug", "", "path")]),
  # `articles/[id].dart` switches on the method: GET and PUT are handled,
  # the remaining verbs fall through to a `methodNotAllowed` response and
  # must NOT be reported. (`test/routes/articles_test.dart` is a test
  # mirror and contributes nothing.)
  Endpoint.new("/articles/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/articles/{id}", "PUT", [Param.new("id", "", "path")]),
  # `ws.dart` upgrades to a WebSocket (`webSocketHandler`), so it serves a
  # single GET (the upgrade handshake) — not the fall-back verb set.
  Endpoint.new("/ws", "GET"),
]

tester = FunctionalTester.new("fixtures/dart/dart_frog/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

# `routes/dashboard_route.dart` is a Flutter UI widget (no `onRequest`
# handler) that happens to live under `routes/`. It must not be reported
# as an HTTP endpoint.
it "ignores routes/ files without an onRequest handler" do
  tester.app.endpoints.any? { |e| e.url == "/dashboard_route" }.should be_false
end

# A `webSocketHandler` route is a single GET with the `ws` protocol, not a
# 5-verb fall-back.
it "narrows a WebSocket route to GET and marks the ws protocol" do
  ws = tester.app.endpoints.select { |e| e.url == "/ws" }
  ws.map(&.method).should eq(["GET"])
  ws.first.protocol.should eq("ws")
end
