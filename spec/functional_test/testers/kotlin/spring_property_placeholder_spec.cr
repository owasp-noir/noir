require "../../func_spec.cr"

# `"\${prop:default}"` mappings resolve against application.yml, falling back
# to the default; an unknown property without one is an empty segment.
expected_endpoints = [
  Endpoint.new("/external", "GET"),
  Endpoint.new("/published", "GET"),
  Endpoint.new("/published/{tenant}/info", "GET", [Param.new("tenant", "", "path")]),
  Endpoint.new("/published/public/info", "GET"),
  Endpoint.new("/v2/pet/{petId}", "GET", [Param.new("petId", "", "path")]),
  Endpoint.new("/v9/orders/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/v9/orders/raw", "GET"),
]

tester = FunctionalTester.new("fixtures/kotlin/spring_property_placeholder/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "spring_property_placeholder route resolution", tags: "functional" do
  it "records the evidence for each reported route" do
    tester.endpoints.find! { |ep| ep.url == "/external" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/published/{tenant}/info" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/published/public/info" }.resolution.should be_nil
    tester.endpoints.find! { |ep| ep.url == "/published" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/v9/orders/raw" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/v2/pet/{petId}" }.resolution.should be_nil
    tester.endpoints.find! { |ep| ep.url == "/v9/orders/{id}" }.resolution.should be_nil
  end
end
