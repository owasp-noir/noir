require "../../func_spec.cr"

# On an ingress gateway, a route with no `match` and a match with no `uri`
# take every path; the header-only match's conditions are its params. The
# mesh-only VirtualService in the same file reports nothing.
catch_all = Endpoint.new("/", "ANY")
catch_all.params = [
  Param.new("x-canary", "1", "header"),
  Param.new("debug", "on", "query"),
]

expected_endpoints = [
  Endpoint.new("/api", "ANY"),
  catch_all,
]

FunctionalTester.new("fixtures/specification/istio_virtualservice_catchall/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
