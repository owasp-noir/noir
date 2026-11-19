require "../../func_spec.cr"

# OpenAPI Generator's go-server on gorilla/mux: a package `var routes =
# Routes{...}` ranged over with `router.Methods(route.Method).Path(...)`.
# The element's method (`strings.ToUpper("Post")`) is the route's verb.
expected_endpoints = [
  Endpoint.new("/v2/", "GET"),
  Endpoint.new("/v2/pet", "POST"),
  Endpoint.new("/v2/pet/{petId}", "GET", [Param.new("petId", "", "path")]),
]

tester = FunctionalTester.new("fixtures/go/mux_route_table/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "reports each table route at its element's line", tags: "functional" do
  tester.endpoints.find! { |ep| ep.url == "/v2/pet" }.details.code_paths.first.line.should eq(46)
end
