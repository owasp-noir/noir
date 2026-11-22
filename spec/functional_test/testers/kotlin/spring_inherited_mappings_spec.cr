require "../../func_spec.cr"

# Mappings declared on an abstract base map under the concrete subclass's
# prefix, never at the root; composed annotations carry their mapping.
expected_endpoints = [
  Endpoint.new("/crud", "POST"),
  Endpoint.new("/crud/list", "GET", [Param.new("page", "0", "query")]),
  Endpoint.new("/crud/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/crud/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/meta-api/plain", "GET"),
  Endpoint.new("/meta-api/audit", "GET"),
]

tester = FunctionalTester.new("fixtures/kotlin/spring_inherited_mappings/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "spring_inherited_mappings route resolution", tags: "functional" do
  it "records the evidence for each reported route" do
    tester.endpoints.find! { |ep| ep.method == "DELETE" && ep.url == "/crud/{id}" }.resolution.should eq({"handler" => "heuristic"})
    tester.endpoints.find! { |ep| ep.url == "/crud/list" }.resolution.should be_nil
  end
end
