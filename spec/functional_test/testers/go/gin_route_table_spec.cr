require "../../func_spec.cr"

# OpenAPI Generator's go-gin-server: routes come from a `[]Route` table that
# `NewRouterWithGinEngine` ranges over, switching on `route.Method`. Each
# element is one route, under the verb of the case that registers it, at
# the element's line, with the params of the element's handler.
expected_endpoints = [
  Endpoint.new("/v2/pet", "POST", [Param.new("Name", "", "json")]),
  Endpoint.new("/v2/pet/:petId", "DELETE", [Param.new("petId", "", "path"), Param.new("api_key", "", "header")]),
  Endpoint.new("/v2/pet/findByStatus", "GET", [Param.new("status", "", "query")]),
]

tester = FunctionalTester.new("fixtures/go/gin_route_table/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "reports each table route at its element's line", tags: "functional" do
  tester.endpoints.find! { |ep| ep.url == "/v2/pet/:petId" }.details.code_paths.first.line.should eq(61)
end
