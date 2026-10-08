require "../../func_spec.cr"

def civetweb_ws(url)
  endpoint = Endpoint.new(url, "GET")
  endpoint.protocol = "ws"
  endpoint
end

resource_params = [
  Param.new("limit", "", "query"),
  Param.new("Content-Type", "", "header"),
]

expected_endpoints = [
  # One C handler dispatching on request_method: one endpoint per method.
  Endpoint.new("/res/*/*", "GET", resource_params),
  Endpoint.new("/res/*/*", "PUT", resource_params),
  Endpoint.new("/res/*/*", "POST", resource_params),
  Endpoint.new("/res/*/*", "DELETE", resource_params),
  Endpoint.new("/exit", "GET"),
  # `$` end anchor dropped.
  Endpoint.new("/cookie", "GET", [
    Param.new("Cookie", "", "header"),
    Param.new("first", "", "cookie"),
  ]),
  civetweb_ws("/websocket"),
  # C++ wrapper: handleGet/handlePost overrides are the methods.
  Endpoint.new("/data", "GET", [Param.new("id", "", "query")]),
  Endpoint.new("/data", "POST", [Param.new("id", "", "query")]),
  Endpoint.new("/status", "GET"),
  civetweb_ws("/ws"),
]

tester = FunctionalTester.new("fixtures/c/civetweb/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "CivetWeb route edge cases", tags: "functional" do
  it "skips extension patterns and auth handlers" do
    urls = tester.app.endpoints.map(&.url)
    urls.any?(&.includes?("foo")).should be_false
    urls.should_not contain("/protected")
  end
end
