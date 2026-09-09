require "../../func_spec.cr"

# gitea's `modules/web` wrapper registers one path with several verbs
# through a `Combo` chain (`m.Combo("/token").Get(h).Delete(h)`) and an
# explicit method list through `Methods("GET, HEAD", "/x", h)`. Neither
# shape is a chi verb call, so before this fixture the 93 Combo chains in
# gitea's API router contributed nothing.
expected_endpoints = [
  Endpoint.new("/robots.txt", "GET"),
  Endpoint.new("/robots.txt", "HEAD"),
  Endpoint.new("/assets/*", "GET"),
  Endpoint.new("/assets/*", "HEAD"),
  Endpoint.new("/assets/*", "OPTIONS"),
  Endpoint.new("/user/token", "GET"),
  Endpoint.new("/user/token", "DELETE"),
  Endpoint.new("/user/actions/secrets", "GET"),
  Endpoint.new("/user/actions/secrets/{secretname}", "GET"),
  Endpoint.new("/user/actions/secrets/{secretname}", "PUT"),
  Endpoint.new("/user/actions/secrets/{secretname}", "DELETE"),
]

FunctionalTester.new("fixtures/go/chi_combo_wrapper/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
