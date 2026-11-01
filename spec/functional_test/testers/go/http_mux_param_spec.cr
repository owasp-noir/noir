require "../../func_spec.cr"

# Routes registered on a `*http.ServeMux` parameter (`RegisterRoutes(mux
# *http.ServeMux)`) are the program's routes; a handler wrapped in a helper
# named for one verb (`hh.GET(h, fallback)`) serves only that verb, and a
# pattern built from a package constant in another file resolves.
expected_endpoints = [
  Endpoint.new("/file/attachments/{uid}", "GET", [Param.new("uid", "", "path")]),
  Endpoint.new("/file/users/{identifier}/export", "GET"),
  Endpoint.new("/healthz", "GET"),
]

FunctionalTester.new("fixtures/go/http_mux_param/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
