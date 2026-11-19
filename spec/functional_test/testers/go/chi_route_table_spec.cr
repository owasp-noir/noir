require "../../func_spec.cr"

# A literal `[]struct{method, path, handler}` table registered in a loop with
# `r.MethodFunc(rt.method, rt.path, rt.handler)`: one route per element, its
# handler the element's. A loop over a table that registers no route (a
# client call) adds nothing.
expected_endpoints = [
  Endpoint.new("/users", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/{id}", "DELETE", [Param.new("id", "", "path")]),
]

tester = FunctionalTester.new("fixtures/go/chi_route_table/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "reports each table route at its element's line", tags: "functional" do
  tester.endpoints.find! { |ep| ep.url == "/users/{id}" }.details.code_paths.first.line.should eq(18)
end
