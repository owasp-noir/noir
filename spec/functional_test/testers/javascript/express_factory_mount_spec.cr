require "../../func_spec.cr"

# A router handed through an aggregator factory (#3575):
#
#   app.use('/api', routes(router))
#   // routes/index.js
#   module.exports = (router) => { users(router); require('./notes')(router) }
#
# `users`, `notes` and the `comments` factory `notes` hands the router on
# to all register on the mounted router, so they are served under `/api`.
# `status(app)` is a plain call on the app, not a mount: `/status` stays.

FunctionalTester.new("fixtures/javascript/express_factory_mount/", {
  :techs     => 1,
  :endpoints => 6,
}, [
  Endpoint.new("/api/v2/users", "GET"),
  Endpoint.new("/api/v2/users", "POST"),
  Endpoint.new("/api/v2/users/:id", "GET"),
  Endpoint.new("/api/v2/notes", "GET"),
  Endpoint.new("/api/v2/notes/:id/comments", "DELETE"),
  Endpoint.new("/status", "GET"),
]).perform_tests
