require "../../func_spec.cr"

# A fastify-cli gateway beside a Hapi catalog service. The Hapi plugin
# modules import nothing, and `server.route({ method, path })` reads as a
# Fastify route config, so Fastify used to claim them (a phantom
# `POST /api/users/` beside Hapi's `POST /api/users`). The closest
# package.json decides which framework owns the file.
FunctionalTester.new("fixtures/javascript/fastify_hapi_sibling/", {
  :techs     => 2,
  :endpoints => 6,
}, [
  Endpoint.new("/api/orders/{orderId}", "DELETE"),
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/api/users/{userId}", "GET"),
  Endpoint.new("/items/{id}", "GET"),
  Endpoint.new("/example/", "GET"),
  Endpoint.new("/", "GET"),
]).perform_tests
