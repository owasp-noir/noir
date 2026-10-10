require "../../func_spec.cr"

# Routers imported by name rather than as a module default:
#
#   const { usersRouter } = require('./routes/users')   // module.exports = { usersRouter }
#   const { router: postsRouter } = require('./posts')  // exports.router = router
#   app.use('/tags', tags.router)                       // module.exports.router = router
#   import { postsRouter as posts } from './posts.js'   // export { router as postsRouter }
#
# The mount prefix is recorded under the exported name, but the routes are
# registered on the router file's local binding, which nothing joined back
# up: every one of these was reported at its bare path (`/list`).

FunctionalTester.new("fixtures/javascript/express_named_export_mount/", {
  :techs     => 1,
  :endpoints => 6,
}, [
  Endpoint.new("/users/list", "GET"),
  Endpoint.new("/posts/recent", "GET"),
  Endpoint.new("/tags/popular", "GET"),
  Endpoint.new("/admin/stats", "GET"),
  Endpoint.new("/audit/log", "GET"),
  Endpoint.new("/api/v1/health", "GET"),
]).perform_tests

FunctionalTester.new("fixtures/javascript/express_named_export_mount_esm/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/users/list", "GET"),
  Endpoint.new("/posts/recent", "GET"),
]).perform_tests
