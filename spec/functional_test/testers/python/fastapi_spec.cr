require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/query/param-required/int", "GET", [Param.new("query", "", "query")]),
  Endpoint.new("/api/items/{item_id}", "PUT", [Param.new("item_id", "", "path"), Param.new("name", "", "json"), Param.new("size", "", "json")]),
  # `Header` maps `_` to `-` unless `convert_underscores=False`, so the name
  # a client actually sends is `hidden-header`, not the Python identifier.
  Endpoint.new("/api/hidden_header", "GET", [Param.new("hidden-header", "", "header")]),
  Endpoint.new("/api/wire_names", "GET", [
    Param.new("x-token", "", "header"),
    Param.new("X-Custom-Auth", "", "header"),
    Param.new("keep_underscores", "", "header"),
    Param.new("q-name", "", "query"),
    Param.new("sess-id", "", "cookie"),
  ]),
  Endpoint.new("/api/aliased_body", "POST", [
    Param.new("userName", "", "json"),
    Param.new("v2Name", "", "json"),
    Param.new("age", "", "json"),
    Param.new("note", "plain", "json"),
  ]),
  Endpoint.new("/api/wire_names/annotated", "GET", [
    Param.new("x-api-key", "", "header"),
    Param.new("X-Tok", "", "header"),
    Param.new("q-x", "", "query"),
  ]),
  Endpoint.new("/api/cookie_examples/", "GET", [Param.new("data", "", "cookie")]),
  Endpoint.new("/api/dummypath", "POST", [Param.new("dummy", "", "json")]),
  # Starlette `Request` accessors read in the handler body.
  Endpoint.new("/api/raw_request", "GET", [
    Param.new("q", "", "query"),
    Param.new("page", "", "query"),
    Param.new("x-token", "", "header"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/api/constant/concat", "GET"),
  Endpoint.new("/api/keyword/fstring", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/api/keyword/items/{item_id}", "GET", [Param.new("item_id", "", "path")]),
  Endpoint.new("/api/dependency/items/{item_id}", "GET", [
    Param.new("q", "", "query"),
    Param.new("item_id", "", "path"),
  ]),
  Endpoint.new("/api/cbv/items/{item_id}", "GET", [
    # `Query(False)` unwraps to the literal it carries, spelled for the
    # wire rather than for Python.
    Param.new("include_meta", "false", "query"),
    Param.new("item_id", "", "path"),
  ]),
  Endpoint.new("/api/constant/registered", "POST"),
  Endpoint.new("/api/constant/registered/{item_id}", "PUT", [
    Param.new("item_id", "", "path"),
    Param.new("q", "", "query"),
    Param.new("payload", "", "json"),
  ]),
  Endpoint.new("/api/external/{item_id}", "PATCH", [
    Param.new("item_id", "", "path"),
    Param.new("q", "", "query"),
    Param.new("payload", "", "json"),
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
  # `Depends()` on the password-flow form reads the two form fields.
  Endpoint.new("/api/login/access-token", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
  ]),
  # Pydantic body models: docstrings, comments and `:` inside a default
  # do not end the field list, base-class fields are inherited, and
  # `Optional[...]` / `Annotated[..., Body()]` still name the model.
  Endpoint.new("/api/orders", "POST", [
    Param.new("customer_id", "", "json"),
    Param.new("label", "", "json"),
    Param.new("quantity", "1", "json"),
  ]),
  Endpoint.new("/api/orders/{order_id}", "PATCH", [
    Param.new("order_id", "", "path"),
    Param.new("customer_id", "", "json"),
    Param.new("label", "", "json"),
  ]),
  Endpoint.new("/api/orders/{order_id}", "PUT", [
    Param.new("order_id", "", "path"),
    Param.new("customer_id", "", "json"),
    Param.new("quantity", "1", "json"),
  ]),
  Endpoint.new("/assets/*", "GET"),
  Endpoint.new("/main", "GET"),
]

tester = FunctionalTester.new("fixtures/python/fastapi/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "marks FastAPI websocket endpoints with ws protocol", tags: "functional" do
  websocket_route = tester.app.endpoints.find { |endpoint| endpoint.url == "/api/ws/{room_id}" }
  websocket_route.should_not be_nil
  websocket_route.try(&.protocol).should eq("ws")

  registered_websocket = tester.app.endpoints.find { |endpoint| endpoint.url == "/api/ws/registered/{channel}" }
  registered_websocket.should_not be_nil
  registered_websocket.try(&.protocol).should eq("ws")
end

it "names the def each FastAPI decorator applies to as the handler", tags: "functional" do
  by_url = tester.app.endpoints.to_h { |ep| { {ep.method, ep.url}, ep.handler } }
  by_url[{"PUT", "/api/items/{item_id}"}].should eq(Handler.new("upsert_item", "./spec/functional_test/fixtures/python/fastapi/api.py", 21))
  by_url[{"GET", "/api/cbv/items/{item_id}"}].should eq(Handler.new("ItemViews.get_item", "./spec/functional_test/fixtures/python/fastapi/api.py", 146))
  by_url[{"POST", "/api/login/access-token"}].try(&.name).should eq("login_access_token")
  by_url[{"POST", "/api/constant/registered"}].try(&.name).should eq("registered_handler")
  # Only the `StaticFiles` mount has no def to name.
  tester.app.endpoints.reject(&.url.ends_with?("/*")).count(&.handler.nil?).should eq(0)
end
