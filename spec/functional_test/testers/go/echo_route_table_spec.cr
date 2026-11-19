require "../../func_spec.cr"

# A literal route table registered in a loop with `e.Add(rt.method, rt.path,
# rt.handler)`: one route per element, under the element's method.
expected_endpoints = [
  Endpoint.new("/items", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/items", "POST"),
  Endpoint.new("/items/:id", "DELETE", [Param.new("id", "", "path")]),
]

tester = FunctionalTester.new("fixtures/go/echo_route_table/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "reports each table route at its element's line", tags: "functional" do
  tester.endpoints.find! { |ep| ep.url == "/items/:id" }.details.code_paths.first.line.should eq(20)
end
