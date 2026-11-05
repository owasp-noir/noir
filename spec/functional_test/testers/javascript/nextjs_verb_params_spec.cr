require "../../func_spec.cr"

# A Pages Router handler that branches on `req.method`: what one verb's
# block reads is not a parameter of the other verbs, and `req.query.itemId`
# under `[itemId].ts` is the path parameter, not a query key.
tester = FunctionalTester.new("fixtures/javascript/nextjs_verb_params/", {
  :techs     => 1,
  :endpoints => 3,
}, [
  Endpoint.new("/api/items/{itemId}", "GET", [Param.new("itemId", "", "path"), Param.new("sort", "", "query")]),
  Endpoint.new("/api/items/{itemId}", "PUT", [Param.new("itemId", "", "path"), Param.new("name", "", "body")]),
  Endpoint.new("/api/items/{itemId}", "DELETE", [Param.new("itemId", "", "path"), Param.new("reason", "", "body")]),
])

tester.perform_tests

describe "Next.js Pages Router verb-branch params", tags: "functional" do
  it "keeps each verb's block to that verb" do
    by_method = tester.app.endpoints.to_h { |ep| {ep.method, ep.params.map { |p| "#{p.param_type}:#{p.name}" }.sort!} }
    by_method["GET"].should_not contain("body:name")
    by_method["PUT"].should_not contain("query:sort")
    by_method["GET"].should contain("body:reason")
  end

  it "does not repeat the dynamic segment as a query parameter" do
    tester.app.endpoints.each do |ep|
      ep.params.any? { |p| p.name == "itemId" && p.param_type == "query" }.should be_false
    end
  end
end
