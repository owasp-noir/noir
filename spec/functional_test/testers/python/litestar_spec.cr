require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{user_id}", "GET", [Param.new("user_id", "", "path")]),
  Endpoint.new("/users", "POST", [Param.new("data", "", "json")]),
  Endpoint.new("/users/{user_id}", "PUT", [Param.new("user_id", "", "path"), Param.new("data", "", "json")]),
  Endpoint.new("/users/{user_id}", "DELETE", [Param.new("user_id", "", "path")]),
  Endpoint.new("/search", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/dependency/{user_id}", "GET", [
    Param.new("user_id", "", "path"),
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/multi", "GET"),
  Endpoint.new("/multi", "POST"),
  Endpoint.new("/ws/{room_id}", "GET", [
    Param.new("room_id", "", "path"),
    Param.new("token", "", "query"),
  ]),
  Endpoint.new("/ws-listener", "GET"),
  Endpoint.new("/headers", "GET", [Param.new("X-Token", "", "header")]),
  Endpoint.new("/cookies", "GET", [Param.new("session", "", "cookie")]),
  Endpoint.new("/inline/summary", "GET", [Param.new("mode", "", "query")]),
  Endpoint.new("/api/items", "GET"),
  Endpoint.new("/api/items/{item_id}", "GET", [Param.new("item_id", "", "path")]),
  Endpoint.new("/admin/reports/{org_id}/{report_id}", "GET", [
    Param.new("org_id", "", "path"),
    Param.new("report_id", "", "path"),
    Param.new("include_meta", "", "query"),
  ]),
  Endpoint.new("/admin/reports/{org_id}", "POST", [
    Param.new("org_id", "", "path"),
    Param.new("data", "", "json"),
  ]),
  Endpoint.new("/external/summary", "GET", [Param.new("mode", "", "query")]),
  Endpoint.new("/absolute/status", "GET"),
]

tester = FunctionalTester.new("fixtures/python/litestar/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "marks Litestar websocket endpoints with ws protocol" do
  websocket_route = tester.app.endpoints.find { |endpoint| endpoint.url == "/ws/{room_id}" }
  websocket_route.should_not be_nil
  websocket_route.try(&.protocol).should eq("ws")
end

it "detects @websocket_listener handlers as ws endpoints" do
  listener_route = tester.app.endpoints.find { |endpoint| endpoint.url == "/ws-listener" }
  listener_route.should_not be_nil
  listener_route.try(&.protocol).should eq("ws")
end
