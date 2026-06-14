require "../../func_spec.cr"

def crow_routes_endpoint(url, method, protocol = "http", params = [] of Param, callees = [] of Callee)
  endpoint = Endpoint.new(url, method, params)
  endpoint.protocol = protocol
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

expected_endpoints = [
  # route_dynamic — params stay bounded to this handler.
  crow_routes_endpoint("/dynamic", "GET", "http", [
    Param.new("foo", "", "query"),
  ], [
    Callee.new("req.url_params.get"),
  ]),
  # The static route that precedes route_dynamic must not absorb its `foo`.
  crow_routes_endpoint("/static", "GET", "http", [
    Param.new("body", "", "json"),
  ]),
  # url_params.get_list / get_dict are query params too.
  crow_routes_endpoint("/list", "GET", "http", [
    Param.new("items", "", "query"),
    Param.new("meta", "", "query"),
  ]),
  # CookieParser context get_cookie → cookie param.
  crow_routes_endpoint("/cookie", "GET", "http", [
    Param.new("session", "", "cookie"),
  ]),
  # Websocket upgrade endpoint.
  crow_routes_endpoint("/ws", "GET", "ws"),
  # Blueprint prefix composition: single-level and nested.
  crow_routes_endpoint("/admin/dashboard", "GET"),
  crow_routes_endpoint("/api/v2/status", "GET"),
]

tester = FunctionalTester.new("fixtures/cpp/crow_routes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})

tester.perform_tests

describe "Crow route discovery edge cases" do
  it "does not leak route_dynamic params into the preceding static route" do
    static = tester.app.endpoints.find { |e| e.url == "/static" && e.method == "GET" }
    static.should_not be_nil
    static.as(Endpoint).params.any? { |p| p.name == "foo" }.should be_false
  end

  it "ignores routes inside block comments" do
    tester.app.endpoints.any? { |e| e.url == "/ghost" }.should be_false
  end

  it "composes blueprint prefixes (and nesting) into the route URL" do
    # The bare `/dashboard` / `/status` literals must not survive on their own.
    tester.app.endpoints.any? { |e| e.url == "/dashboard" }.should be_false
    tester.app.endpoints.any? { |e| e.url == "/status" }.should be_false
    tester.app.endpoints.any? { |e| e.url == "/admin/dashboard" }.should be_true
    tester.app.endpoints.any? { |e| e.url == "/api/v2/status" }.should be_true
  end
end
