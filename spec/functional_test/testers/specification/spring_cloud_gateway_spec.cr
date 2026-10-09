require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/users/**", "GET"),
  Endpoint.new("/api/users/**", "POST"),
  # Expanded `name`/`args` form under `spring.cloud.gateway.server.webflux`.
  Endpoint.new("/api/orders/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/carts/**", "DELETE"),
  # `.properties` form; no `Method` predicate means any verb.
  Endpoint.new("/reports/**", "ANY"),
  Endpoint.new("/search", "PUT"),
  # `server.webflux.routes[0]` is not `routes[0]`; `methods: GET,POST` is a list.
  Endpoint.new("/next/**", "GET"),
  Endpoint.new("/next/**", "POST"),
]

FunctionalTester.new("fixtures/specification/spring_cloud_gateway/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
