require "../../func_spec.cr"

# A literal `[]route{pattern, handler}` table registered in a loop with
# `mux.HandleFunc(rt.pattern, rt.handler)`: one route per element, with the
# method its Go 1.22 pattern names and its handler's params.
expected_endpoints = [
  Endpoint.new("/users", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/users", "POST", [Param.new("name", "", "form")]),
  Endpoint.new("/users/{id}", "DELETE", [Param.new("id", "", "path")]),
]

tester = FunctionalTester.new("fixtures/go/http_route_table/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "reports each table route at its element's line", tags: "functional" do
  tester.endpoints.find! { |ep| ep.url == "/users/{id}" }.details.code_paths.first.line.should eq(15)
end
