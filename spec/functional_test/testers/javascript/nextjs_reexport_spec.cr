require "../../func_spec.cr"

# Next.js app-router edge cases:
#   * `export * from "<route>"` re-exports the target route's verb
#     handlers — resolved cross-file and emitted at the re-exporting
#     file's own URL (`/api/projects` from `(old)/projects/route.ts`).
#   * `export const { POST } = serve(...)` destructures handlers from a
#     factory call.
expected_endpoints = [
  Endpoint.new("/api/analytics", "GET"),
  Endpoint.new("/api/projects", "GET"),
  Endpoint.new("/api/workflows", "POST"),
]

FunctionalTester.new("fixtures/javascript/nextjs_reexport/", {
  :techs     => 1,
  :endpoints => 3,
}, expected_endpoints).perform_tests
