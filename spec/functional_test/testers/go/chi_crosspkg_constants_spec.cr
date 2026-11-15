require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/scim/v2/ResourceTypes", "GET"),
  Endpoint.new("/scim/v2/Schemas", "GET"),
  Endpoint.new("/scim/helper-base/helper", "GET"),
  Endpoint.new("/scim/mount-base/mounted", "GET"),
  Endpoint.new("/variable", "GET"),
  Endpoint.new("/function", "GET"),
  Endpoint.new("/third-party", "GET"),
]

tester = FunctionalTester.new("fixtures/go/chi_crosspkg_constants/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "chi cross-package string constants", tags: "functional" do
  it "resolves only in-module exported string constants" do
    resolved = tester.endpoints.reject(&.resolution).map { |ep| "#{ep.method} #{ep.url}" }.sort!
    resolved.should eq([
      "GET /scim/helper-base/helper",
      "GET /scim/mount-base/mounted",
      "GET /scim/v2/ResourceTypes",
      "GET /scim/v2/Schemas",
    ])

    unresolved = tester.endpoints.select(&.resolution)
    unresolved.map { |ep| "#{ep.method} #{ep.url}" }.sort!.should eq([
      "GET /function",
      "GET /third-party",
      "GET /variable",
    ])
    unresolved.map(&.resolution).uniq!.should eq([{"prefix" => "unresolved"}])
    tester.endpoints.none? { |ep| ep.url == "/typed" }.should be_true
  end
end
