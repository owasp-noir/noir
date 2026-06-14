require "../../func_spec.cr"

# Exercises the controller-oriented Hummingbird routing styles:
#   * `addRoutes(to: router.group("api/todos"))` + fluent builder chains
#   * `RouteCollection` mounted via `addRoutes(_:atPath:)`
#   * builder chains that resume across trailing closures
#   * builder chains that *open* with `.add(middleware:)`
#   * `.on(method:)`, HEAD and `.ws` verbs
# The fixture also contains non-router `.get(...)`/`.delete(...)` calls
# (environment.get, storage.get, repository.delete) that must NOT surface
# as endpoints, and a `vapor/*` ecosystem dependency that must NOT tag the
# project as Vapor.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/status", "HEAD"),
  Endpoint.new("/socket", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/:id", "GET"),
  Endpoint.new("/users/session/login", "POST"),
  Endpoint.new("/users/session/logout", "POST"),
  Endpoint.new("/api/todos", "GET"),
  Endpoint.new("/api/todos/:id", "GET"),
  Endpoint.new("/api/todos", "POST"),
  Endpoint.new("/api/todos/:id", "PATCH"),
  Endpoint.new("/api/todos/:id", "DELETE"),
  Endpoint.new("/api/todos/me", "GET"),
  Endpoint.new("/api/todos/logout", "POST"),
]

FunctionalTester.new("fixtures/swift/hummingbird_controllers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
