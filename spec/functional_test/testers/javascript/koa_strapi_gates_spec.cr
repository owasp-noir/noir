require "../../func_spec.cr"

# Koa's Strapi-style route-object pass has two gates:
#   * a package whose package.json names `@strapi/*` is the strapi tech's, which
#     reports the route at its served `/api/...` URL — the raw
#     `POST /config/ratelimit/enable` copy is not served;
#   * test files are skipped, as in the verb-DSL pass
#     (`koa-app/__tests__/routes.test.js`).
# `koa-app/routes/items.js` is the same declarative table in a project that is
# not a Strapi package, and is still read.
expected_endpoints = [
  Endpoint.new("/_health", "GET"),
  Endpoint.new("/table/items", "GET"),
  Endpoint.new("/api/config/ratelimit/enable", "POST"),
]

FunctionalTester.new("fixtures/javascript/koa_strapi_gates/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
