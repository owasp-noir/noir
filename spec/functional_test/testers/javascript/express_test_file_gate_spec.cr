require "../../func_spec.cr"

# Test files are not part of the attack surface, whatever they import:
#   * `test/orders_spec.js`     — `_spec.` suffix plus a describe/supertest harness
#   * `test/Router.js`          — a plain-named mocha suite that imports express
#   * `test/fixtures/apps/...`  — a fixture app only the test run loads
#   * `vitest.setup.ts`         — throwaway `@epic-web/test-server` routes
#   * `types/reply.tst.ts`      — tstyche type tests
#   * `src/middleware/session-timeout.test.ts` — a terminal `app.use('/api', …)`
#     handler, read by Express's own use-handler pass rather than the extractor
# `routes/ab_test.js` is an A/B-test feature router (express import, no
# harness) and keeps its route.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/api/orders", "POST"),
  Endpoint.new("/assign", "POST"),
] + %w[GET POST PUT DELETE PATCH HEAD OPTIONS].map { |method| Endpoint.new("/files", method) }

FunctionalTester.new("fixtures/javascript/express_test_file_gate/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
