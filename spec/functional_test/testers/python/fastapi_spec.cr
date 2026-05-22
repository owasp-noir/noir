require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/query/param-required/int", "GET", [Param.new("query", "", "query")]),
  Endpoint.new("/api/items/{item_id}", "PUT", [Param.new("item_id", "", "path"), Param.new("name", "", "form"), Param.new("size", "", "form")]),
  Endpoint.new("/api/hidden_header", "GET", [Param.new("hidden_header", "", "header")]),
  Endpoint.new("/api/cookie_examples/", "GET", [Param.new("data", "", "cookie")]),
  Endpoint.new("/api/dummypath", "POST", [Param.new("dummy", "", "json")]),
  Endpoint.new("/api/constant/concat", "GET"),
  Endpoint.new("/api/keyword/fstring", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/api/keyword/items/{item_id}", "GET", [Param.new("item_id", "", "path")]),
  Endpoint.new("/api/dependency/items/{item_id}", "GET", [
    Param.new("q", "", "query"),
    Param.new("item_id", "", "path"),
  ]),
  Endpoint.new("/api/cbv/items/{item_id}", "GET", [
    Param.new("include_meta", "False", "query"),
    Param.new("item_id", "", "path"),
  ]),
  Endpoint.new("/api/constant/registered", "POST"),
  Endpoint.new("/api/constant/registered/{item_id}", "PUT", [
    Param.new("item_id", "", "path"),
    Param.new("q", "", "query"),
    Param.new("payload", "", "form"),
  ]),
  Endpoint.new("/api/external/{item_id}", "PATCH", [
    Param.new("item_id", "", "path"),
    Param.new("q", "", "query"),
    Param.new("payload", "", "form"),
  ]),
  Endpoint.new("/api/tenants/{tenant_id}/registered", "GET", [
    Param.new("tenant_id", "", "path"),
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/api/ws/{room_id}", "GET", [
    Param.new("room_id", "", "path"),
    Param.new("token", "", "query"),
  ]),
  Endpoint.new("/api/ws/registered/{channel}", "GET", [
    Param.new("channel", "", "path"),
    Param.new("client_id", "", "query"),
  ]),
  Endpoint.new("/v1/local/status", "GET", [
    Param.new("region", "", "query"),
  ]),
  Endpoint.new("/assets/*", "GET"),
  Endpoint.new("/main", "GET"),
]

tester = FunctionalTester.new("fixtures/python/fastapi/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "marks FastAPI websocket endpoints with ws protocol" do
  websocket_route = tester.app.endpoints.find { |endpoint| endpoint.url == "/api/ws/{room_id}" }
  websocket_route.should_not be_nil
  websocket_route.try(&.protocol).should eq("ws")

  registered_websocket = tester.app.endpoints.find { |endpoint| endpoint.url == "/api/ws/registered/{channel}" }
  registered_websocket.should_not be_nil
  registered_websocket.try(&.protocol).should eq("ws")
end
