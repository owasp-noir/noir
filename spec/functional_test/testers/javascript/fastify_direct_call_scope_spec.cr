require "../../func_spec.cr"

# A plain call handed the instance is a mount only when the called
# function routes or registers on that parameter, and only that function's
# own registrations inherit the prefix:
#
#   register(async (admin) => { auditHook(admin); hashPassword(admin) }, { prefix: "/admin" })
#
# `auditHook` (adds a hook) and `hashPassword` (hashes its argument) share
# modules with real plugins (`usersRouter`, `utilRouter`); neither the
# module's other plugins nor their children move under `/admin`.
FunctionalTester.new("fixtures/javascript/fastify_direct_call_scope/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/users/profile/me", "GET"),
  Endpoint.new("/o/x", "GET"),
]).perform_tests
