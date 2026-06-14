require "../../func_spec.cr"

# Modular tRPC layout that large apps (documenso, cal.com, ...) use:
#   * a composition root (`appRouter = router({ user: userRouter })`) with
#     NO inline procedure — must still be detected and compose dotted paths;
#   * procedures defined in their own files and referenced by name
#     (`get: getUserRoute`) — resolved cross-file;
#   * an inline nested router (`profile: router({ update: ... })`);
#   * a plain-object nested router (`settings: { read: ... }`, tRPC v11);
#   * a `endpoint: `/${string}`` TS *type* that must NOT hijack the prefix
#     (it stays the default /api/trpc).
expected_endpoints = [
  Endpoint.new("/api/trpc/user.get", "GET", [Param.new("id", "", "query")]),
  Endpoint.new("/api/trpc/user.profile.update", "POST", [Param.new("displayName", "", "body")]),
  Endpoint.new("/api/trpc/user.settings.read", "GET"),
  Endpoint.new("/api/trpc/admin.stats", "GET"),
]

FunctionalTester.new("fixtures/typescript/trpc_modular/", {
  :techs     => 1,
  :endpoints => 4,
}, expected_endpoints).perform_tests
