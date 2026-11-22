require "../../func_spec.cr"

# `APIRouter(prefix="/v1")` handed to a helper whose `app.include_router`
# names a parameter: no app is seen to include it, yet the routers it
# includes (and theirs in turn) are served under `/v1`, not bare.
expected_endpoints = [
  Endpoint.new("/v1/items/{item_id}", "GET", [Param.new("item_id", "", "path")]),
  # `from portal import router` names the package `__init__.py`, and
  # `from ..session import router` the parent package's module.
  Endpoint.new("/v1/portal/orders/", "GET"),
  Endpoint.new("/v1/portal/account/me", "GET"),
  Endpoint.new("/v1/portal/account/session/start", "POST"),
  Endpoint.new("/v1/checkouts/client/{client_secret}", "GET", [Param.new("client_secret", "", "path")]),
  Endpoint.new("/v1/checkouts/custom/client/{client_secret}", "GET", [Param.new("client_secret", "", "path")]),
  # A router nothing includes keeps its own prefix.
  Endpoint.new("/standalone/ping", "GET"),
  Endpoint.new("/events", "POST", [Param.new("limit", "", "query")]),
  Endpoint.new("/news", "POST", [Param.new("limit", "", "query")]),
  # A dead router including `items` adds no `/legacy/items/...`.
  Endpoint.new("/legacy/ping", "GET"),
]

tester = FunctionalTester.new("fixtures/python/fastapi_unmounted_router_root/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "fastapi_unmounted_router_root route resolution", tags: "functional" do
  it "records the evidence for each reported route" do
    tester.endpoints.find! { |ep| ep.url == "/v1/items/{item_id}" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/standalone/ping" }.resolution.should eq({"registration" => "unresolved"})
  end
end
