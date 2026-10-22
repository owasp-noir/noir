require "../../func_spec.cr"

# The mount has no `endpoint` option, so the default /api/trpc applies. Stories
# and non-tRPC modules in the same package carry `endpoint:` values (an S3 URL,
# a "GET /path" label, a SCIM path) that used to be adopted as the mount path
# of every router.
expected_endpoints = [
  Endpoint.new("/api/trpc/health", "GET", [] of Param),
  Endpoint.new("/api/trpc/echo", "POST", [
    Param.new("message", "", "body"),
  ]),
]

FunctionalTester.new("fixtures/typescript/trpc_prefix_decoy/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
