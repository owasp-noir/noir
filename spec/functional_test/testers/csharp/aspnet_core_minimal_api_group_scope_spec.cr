require "../../func_spec.cr"

# Two extension methods in one file that each declare `var group`, and a
# `this RouteGroupBuilder group` parameter beside them: every `group` is the
# one of its own method. A top-level local function sees the top-level group.
expected_endpoints = [
  Endpoint.new("/revisions/current", "GET", [Param.new("api-version", "", "query")]),
  Endpoint.new("/unversioned", "GET"),
  Endpoint.new("/selection", "GET"),
  Endpoint.new("/summary", "GET"),
  Endpoint.new("/shared/report", "GET"),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/orders", "GET"),
  Endpoint.new("/api/orders", "POST"),
  Endpoint.new("/api/v1/products", "GET"),
  Endpoint.new("/api/v1/products/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/shared/ping", "GET"),
]

tester = FunctionalTester.new("fixtures/csharp/aspnet_core_minimal_api_group_scope/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "aspnet_core_minimal_api_group_scope route resolution", tags: "functional" do
  it "records the evidence for each reported route" do
    selection = tester.endpoints.find! { |ep| ep.url == "/selection" }
    selection.resolution.should be_nil
    selection.handler.try { |handler| {handler.name, handler.line} }.should eq({"First.Status", 36})
    tester.endpoints.find! { |ep| ep.url == "/summary" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/shared/report" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/shared/ping" }.resolution.should be_nil
  end
end
