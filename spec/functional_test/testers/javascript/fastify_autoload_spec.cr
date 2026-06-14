require "../../func_spec.cr"

# `@fastify/autoload` mounts each route file under a prefix derived from
# its directory path relative to the autoload `dir`. A route registered
# as `app.get('/:id')` inside `routes/api/tasks/index.ts` is served at
# `/api/tasks/:id`; a route file directly in `routes/` keeps `/`.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/api/tasks/:id", "GET"),
  Endpoint.new("/api/tasks/", "POST"),
]

FunctionalTester.new("fixtures/javascript/fastify_autoload/", {
  :techs => 1,
}, expected_endpoints).perform_tests
