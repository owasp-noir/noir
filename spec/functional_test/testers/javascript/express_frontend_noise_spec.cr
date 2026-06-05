require "../../func_spec.cr"

# Regression test for issue #1903:
#   "Express analyzer scans unrelated frontend/generated JS after a
#    single Express server is detected."
#
# A tiny Express server (app.js) sits next to the kind of files a real
# monorepo carries around it:
#
#   * src/lib/app-bundle.js     — a minified webpack bundle (one 8 KB
#                                 line) whose packed `app.get('/bundle-leak')`
#                                 must NOT be tokenized or extracted.
#   * public/widget.js          — a browser script under public/ whose
#                                 `app.get('/public-leak')` is static
#                                 output, not a route.
#   * src/datasources/UsersAPI.ts — an Apollo RESTDataSource whose
#                                 `this.get('/ds-leak/...')` calls are
#                                 OUTBOUND requests, not registrations.
#
# Only the two real Express routes from app.js may survive. Before the
# fix, the bundle alone could dominate scan time and every `*-leak`
# shape leaked as a phantom endpoint.

expected_endpoints = [
  Endpoint.new("/api/health", "GET"),
  Endpoint.new("/api/login", "POST", [
    Param.new("username", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/javascript/express_frontend_noise/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
