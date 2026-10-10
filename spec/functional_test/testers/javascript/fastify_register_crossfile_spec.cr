require "../../func_spec.cr"

# Fastify plugins registered from another file:
#
#   fastify.register(apiRoutes, { prefix: '/api' })          // const apiRoutes = require('./routes/api')
#   fastify.register(adminRoutes, { prefix: '/admin' })      // const { adminRoutes } = require(...)
#   fastify.register(require('./users'), { prefix: '/users' }) // inside routes/api.js
#
# Only same-file plugins had their prefix applied; every route in a plugin
# file was reported at its bare path (`/:id` instead of `/api/users/:id`).

FunctionalTester.new("fixtures/javascript/fastify_register_crossfile/", {
  :techs     => 1,
  :endpoints => 5,
}, [
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/users/", "POST"),
  Endpoint.new("/admin/stats", "GET"),
  Endpoint.new("/health", "GET"),
]).perform_tests
