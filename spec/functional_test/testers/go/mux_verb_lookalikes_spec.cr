require "../../func_spec.cr"

# Regression: gorilla/mux's analyzer ran the shared verb-call decoder, so
# `env.Get("_APP_SCANNER", config.EnableOn)` came out as
# `GET /_APP_SCANNER` and `store.Put("timeout", timeout)` as `PUT /timeout`.
# The fixture also carries the other look-alikes seen in MinIO and
# Mattermost (`log.Any`, `cache.Get`, a `router.Get("users")` lookup).
expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST"),
]

FunctionalTester.new("fixtures/go/mux_verb_lookalikes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
