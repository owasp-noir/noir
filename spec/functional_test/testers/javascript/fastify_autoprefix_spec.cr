require "../../func_spec.cr"

# `@fastify/autoload` with `dirNameRoutePrefix: false`: directory names do
# NOT become prefixes, and a file's `export const autoPrefix = '/_app'`
# supplies the prefix instead. So `routes/status.js` -> `/_app/status`,
# while `routes/redirect/index.js` (no autoPrefix) -> `/go`, NOT
# `/redirect/go`.
expected_endpoints = [
  Endpoint.new("/_app/status", "GET"),
  Endpoint.new("/go", "GET"),
]

FunctionalTester.new("fixtures/javascript/fastify_autoprefix/", {
  :techs     => 1,
  :endpoints => 2,
}, expected_endpoints).perform_tests
