require "../../func_spec.cr"

# `RouterModule.register` mounts a module's controllers under its path:
# a constant imported from another file, a plain string, `children`
# nesting, and a module that is not registered (its controller keeps its own
# path). A commented-out route entry mounts nothing.
expected_endpoints = [
  Endpoint.new("/api/v2/me", "GET"),
  Endpoint.new("/api/private/me", "GET"),
  Endpoint.new("/api/private/me/profile", "POST"),
  Endpoint.new("/api/private/inner", "GET"),
  Endpoint.new("/other", "GET"),
  Endpoint.new("/optional", "GET"),
  Endpoint.new("/quoted{literal}", "GET", [Param.new("literal", "", "path")]),
  Endpoint.new("/template{NAME}", "GET", [Param.new("NAME", "", "path")]),
  Endpoint.new("/branch", "GET"),
]

tester = FunctionalTester.new("fixtures/javascript/nestjs_router_module/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "nestjs_router_module route resolution", tags: "functional" do
  it "records the evidence for each reported route" do
    tester.endpoints.find! { |ep| ep.url == "/other" }.resolution.should be_nil
    tester.endpoints.find! { |ep| ep.url == "/quoted{literal}" }.resolution.should be_nil
    tester.endpoints.find! { |ep| ep.url == "/branch" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/template{NAME}" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/optional" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/api/private/me" }.resolution.should be_nil
    tester.endpoints.find! { |ep| ep.url == "/api/private/inner" }.resolution.should be_nil
  end
end
