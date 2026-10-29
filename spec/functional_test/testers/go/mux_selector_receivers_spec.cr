require "../../func_spec.cr"

# gorilla/mux routers held in struct fields (`api.BaseRoutes.Users`, set in
# main.go and registered on in user.go, as mattermost does), a one-field
# router (`s.R`), a subrouter passed to a helper
# (`InitParam(r.PathPrefix(...).Subrouter())`) and an interpreted-string
# regex whose escapes Go keeps (`"[\\_\\-\\.]"` is `[\_\-\.]`).
expected_endpoints = [
  Endpoint.new("/api/v4/users/ids", "POST"),
  Endpoint.new("/api/v4/users/stats", "GET"),
  Endpoint.new("/local/ping", "GET"),
  Endpoint.new("/field", "GET"),
  Endpoint.new("/api/param/x", "GET"),
  Endpoint.new("/plugins/{plugin_id:[A-Za-z0-9\\_\\-\\.]+}", "GET", [Param.new("plugin_id", "", "path")]),
  Endpoint.new("/raw/{id:[a-z\\-\\.]+}", "GET", [Param.new("id", "", "path")]),
  # `\xNN` escapes are bytes: "/\xc3\xa9t\xc3\xa9" is the UTF-8 for /été.
  Endpoint.new("/été", "GET"),
]

FunctionalTester.new("fixtures/go/mux_selector_receivers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
