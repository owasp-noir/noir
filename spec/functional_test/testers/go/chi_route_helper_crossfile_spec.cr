require "../../func_spec.cr"

# A `Route` helper declared in another file or package keeps the prefix of
# the call site that hands it the router, whether it is the callback
# (`r.Route("/p", api.Register)`) or called from the closure. Its routes stay
# in their own file, with the params of their handlers.
expected_endpoints = [
  Endpoint.new("/c1-pkg/items", "GET"),
  Endpoint.new("/c2-otherfile/z", "GET"),
  Endpoint.new("/c2-otherfile/find", "GET", [Param.new("term", "", "query")]),
  Endpoint.new("/c3-closure-otherfile/z2", "GET"),
  Endpoint.new("/c4-closure-pkg/items2", "GET"),
  Endpoint.new("/c5-mount-var/s", "GET"),
  Endpoint.new("/c6-closure-samefile/same", "GET"),
  Endpoint.new("/c8-again/z2", "GET"),
  Endpoint.new("/c7-items3", "GET"),
]

tester = FunctionalTester.new("fixtures/go/chi_route_helper_crossfile/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "reports a helper's route at its line in the helper's file", tags: "functional" do
  path = tester.endpoints.find! { |ep| ep.url == "/c2-otherfile/find" }.details.code_paths.first
  path.path.should end_with("routes_other.go")
  path.line.should eq(12)
end
