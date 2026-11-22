require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/ops/v2/constant/path", "GET"),
  Endpoint.new("/ops/uptime", "GET"),
  Endpoint.new("/public/entry", "GET"),
  Endpoint.new("/verified/entry", "GET"),
  Endpoint.new("/literal/path", "GET"),
  Endpoint.new("/constant/path", "GET"),
  Endpoint.new("/api/v1/path", "GET"),
  Endpoint.new("/unread", "GET"),
  Endpoint.new("/router-v1/router", "GET"),
  Endpoint.new("/f-v1/fstring", "GET"),
  Endpoint.new("/env-v1/env", "GET"),
  Endpoint.new("/call", "GET"),
  Endpoint.new("/gap", "GET"),
  Endpoint.new("/relative", "GET"),
  Endpoint.new("/variable", "GET"),
  Endpoint.new("/leading-runtime", "GET"),
  Endpoint.new("/include-v1/include", "GET"),
  Endpoint.new("/include-unread", "GET"),
  Endpoint.new("/nested/health", "GET"),
  Endpoint.new("/nested/mount/child/nested-path", "GET"),
  Endpoint.new("/cross/outer/nested/external/item", "GET"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/subapp-health", "GET"),
]

tester = FunctionalTester.new("fixtures/python/fastapi_prefix_resolution/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "FastAPI prefix resolution", tags: "functional" do
  it "marks unread prefixes and keeps only safe slash-rooted tails" do
    marked = tester.endpoints.select(&.resolution).map { |ep| "#{ep.method} #{ep.url}" }.sort!
    marked.should eq([
      "GET /api/v1/path",
      "GET /call",
      "GET /cross/outer/nested/external/item",
      "GET /env-v1/env",
      "GET /f-v1/fstring",
      "GET /gap",
      "GET /include-unread",
      "GET /include-v1/include",
      "GET /leading-runtime",
      "GET /nested/mount/child/nested-path",
      "GET /ops/uptime",
      "GET /ops/v2/constant/path",
      "GET /public/entry",
      "GET /relative",
      "GET /router-v1/router",
      "GET /subapp-health",
      "GET /unread",
      "GET /variable",
    ])
    tester.endpoints.select(&.resolution).each do |endpoint|
      heuristic = %w[/api/v1/path /env-v1/env /include-v1/include /nested/mount/child/nested-path /ops/uptime /ops/v2/constant/path /public/entry /router-v1/router]
      expected = heuristic.includes?(endpoint.url) ? Endpoint::RESOLUTION_HEURISTIC : Endpoint::RESOLUTION_UNRESOLVED
      evidence = {"prefix" => expected}
      # Both routers are defined in main.py and omitted from its includes.
      evidence["registration"] = "unresolved" if endpoint.url.in?("/variable", "/leading-runtime")
      endpoint.resolution.should eq(evidence)
    end
  end

  it "leaves exact literal and imported prefixes unmarked" do
    resolved = tester.endpoints.reject(&.resolution).map(&.url).sort!
    resolved.should eq(["/constant/path", "/health", "/literal/path", "/nested/health", "/verified/entry"])
  end
end
