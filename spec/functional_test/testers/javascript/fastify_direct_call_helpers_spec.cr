require "../../func_spec.cr"

# A plugin entered by a direct call that hands its instance to a same-file
# helper (`registerAll(api)` -> `registerLocal(server)`): the helper's
# routes and registrations take the prefix too. An expression-bodied arrow
# (`getUserId = (server) => server.user`) is no plugin, and the next
# function's body is not taken for its own.
FunctionalTester.new("fixtures/javascript/fastify_direct_call_helpers/", {
  :techs     => 1,
  :endpoints => 3,
}, [
  Endpoint.new("/api/local", "GET"),
  Endpoint.new("/api/lc/kid", "GET"),
  Endpoint.new("/profile/me", "GET"),
]).perform_tests
