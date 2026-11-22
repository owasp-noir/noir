require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v1/prefix-users", "GET"),
  Endpoint.new("/prefix-orders", "POST"),
  Endpoint.new("/internal/prefix-health", "GET"),
  Endpoint.new("/fixed/prefix-factory", "GET"),
  Endpoint.new("/{runtimeBase}/v2/prefix-nested", "GET", [Param.new("runtimeBase", "", "path")]),
  Endpoint.new("/prefix-plain", "GET"),
  Endpoint.new("/preview-only", "GET"),
  Endpoint.new("/separate", "GET"),
]
tester = FunctionalTester.new("fixtures/javascript/express_unread_prefix/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Express unread prefix resolution", tags: "functional" do
  it "marks runtime mounts across files and nested local routers, leaving read prefixes unmarked" do
    detached, others = tester.endpoints.partition(&.url.in?("/preview-only", "/separate"))
    detached.each { |ep| ep.resolution.should eq({"registration" => "unresolved"}) }
    others.select(&.resolution).map { |ep| "#{ep.method} #{ep.url}" }.sort!.should eq([
      "GET /v1/prefix-users", "GET /{runtimeBase}/v2/prefix-nested", "POST /prefix-orders",
    ])
    others.compact_map(&.resolution).uniq!.should eq([{"prefix" => "unresolved"}])
    tester.endpoints.to_json.should_not contain(Noir::JSMountPrefix::UNREAD)
  end
end
