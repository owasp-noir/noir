require "../../func_spec.cr"

# Outbound HTTP-client calls carry the shape of a route registration
# (`receiver.verb('/path', arg)`) but nothing serves them:
#   * web/stores/AuthStore.ts       — MobX store, `client.post(...)` (mobx/@sentry/react)
#   * web/legacy/admin.js           — jQuery `$.post` and `AJAX.put`
#   * services/project.service.ts   — `this.post(...)` in an API client class
#   * sdk/pet.service.ts            — an injected `this.httpClient.post(...)`
#   * loadtest/script.js            — k6 `http.post(...)`
#   * src/tests/frontend/specs/     — a browser-side helper
# A receiver the file builds from express() keeps its routes, whatever its name.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/api/items", "POST"),
  Endpoint.new("/named-http", "GET"),
]

FunctionalTester.new("fixtures/javascript/express_outbound_clients/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
