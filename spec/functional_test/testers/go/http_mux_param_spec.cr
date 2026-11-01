require "../../func_spec.cr"

# Routes registered on a `*http.ServeMux` parameter (`RegisterRoutes(mux
# *http.ServeMux)`) are the program's routes, under the prefix the caller
# mounts that mux at (`mux.Handle("/api/", http.StripPrefix("/api", apiMux))`);
# a mount whose pattern does not resolve drops them rather than report them
# at the wrong path. A helper named for one verb (`httphandler.GET(h, nil)`)
# serves only that verb, unless it hands the others to a fallback; a
# pattern built from a package constant in another file resolves.
attachment_verbs = %w[GET POST PUT PATCH DELETE HEAD OPTIONS]
expected_endpoints = attachment_verbs.map { |verb| Endpoint.new("/file/attachments/{uid}", verb, [Param.new("uid", "", "path")]) } + [
  Endpoint.new("/file/users/{identifier}/export", "GET"),
  Endpoint.new("/healthz", "GET"),
  Endpoint.new("/api/users", "GET"),
]

FunctionalTester.new("fixtures/go/http_mux_param/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
