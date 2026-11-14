require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v0/ping", "GET"),
  Endpoint.new("/v1/status", "GET"),
  Endpoint.new("/root", "GET"),
  Endpoint.new("/gap", "GET"),
  Endpoint.new("/v1/admin/users", "GET"),
  Endpoint.new("/v2/users", "GET"),
  Endpoint.new("/users", "GET"),
]

tester = FunctionalTester.new("fixtures/go/gin_inline_group_prefix/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Gin inline group prefix resolution", tags: "functional" do
  it "marks unread inline prefixes and keeps fully literal groups unmarked" do
    tester.endpoints.select(&.resolution).map { |ep| "#{ep.method} #{ep.url}" }.sort!.should eq([
      "GET /gap",
      "GET /root",
      "GET /users",
      "GET /v1/admin/users",
      "GET /v1/status",
      "GET /v2/users",
    ])
    tester.endpoints.reject(&.resolution).map { |ep| "#{ep.method} #{ep.url}" }.should eq(["GET /v0/ping"])
    tester.endpoints.compact_map(&.resolution).uniq!.should eq([{"prefix" => "unresolved"}])
  end

  it "does not report the non-router Group lookalikes" do
    tester.endpoints.map(&.url).should_not contain("/column")
    tester.endpoints.map(&.url).should_not contain("/user/\\d+")
  end
end
