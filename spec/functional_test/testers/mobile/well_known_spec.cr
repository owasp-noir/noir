require "../../func_spec.cr"

# Server-side universal-link declarations: /.well-known/assetlinks.json
# (Android App Links) and apple-app-site-association (iOS Universal Links).
# These keep method = "GET"; the semantics live in protocol = "universal-link".
# Endpoint is a struct, so build via a Proc that mutates a local and returns
# it (a `.tap` block would mutate a copy and not persist).
build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "GET", params)
  ep.protocol = "universal-link"
  ep
end

no_params = [] of Param

expected_endpoints = [
  # assetlinks.json — handle_all_urls grants the whole hosting domain.
  build.call("/*", no_params),
  # apple-app-site-association legacy `paths` (incl. a NOT exclusion).
  build.call("/buy/*", no_params),
  build.call("/private/*", no_params),
  build.call("/help/website/*", no_params),
  # iOS 13+ `components` form: path + a `?` query matcher, plus an exclusion.
  build.call("/articles/*", [Param.new("articleNumber", "", "query")]),
  build.call("/secret/*", no_params),
]

FunctionalTester.new("fixtures/mobile/well_known/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
