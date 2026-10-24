require "../../func_spec.cr"

# An Outline-shaped Koa app: koa-mount apps (`app.use(mount("/api", api))`)
# wrapping @koa/router routers that mount sub-routers at `/` through a
# default re-export barrel, with slash-less RPC paths
# (`router.post("documents.info", …)`) that koa-router serves as
# `/documents.info` under the mount.
expected_endpoints = [
  Endpoint.new("/api/documents.info", "POST", [Param.new("id", "", "json")]),
  Endpoint.new("/api/documents.create", "POST", [Param.new("title", "", "json")]),
  Endpoint.new("/api/auth.config", "POST"),
  Endpoint.new("/oauth/register", "POST"),
  Endpoint.new("/locales/:lng.json", "GET", [Param.new("lng", "", "path")]),
  Endpoint.new("/s/:shareId", "GET", [Param.new("shareId", "", "path")]),
  Endpoint.new("/s/:shareId/doc/:documentSlug", "GET", [Param.new("shareId", "", "path"), Param.new("documentSlug", "", "path")]),
]

tester = FunctionalTester.new("fixtures/javascript/koa_mount_rpc/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Koa mount + RPC routes", tags: "functional" do
  endpoint = ->(method : String, url : String) { tester.endpoints.find! { |ep| ep.method == method && ep.url == url } }
  handler = ->(method : String, url : String) do
    h = endpoint.call(method, url).handler.should_not(be_nil)
    {h.name, h.path.should_not(be_nil).split("koa_mount_rpc/").last, h.line}
  end

  it "reports an inline closure as the handler at the line it starts on" do
    handler.call("POST", "/api/documents.info").should eq({"closure", "server/api/documents/documents.ts", 10})
    handler.call("POST", "/api/documents.create").should eq({"closure", "server/api/documents/documents.ts", 20})
    handler.call("GET", "/locales/:lng.json").should eq({"closure", "server/routes.ts", 8})
    handler.call("GET", "/s/:shareId").should eq({"renderShare", "server/share.ts", 1})
  end

  it "keeps only the path params the route's own template binds" do
    endpoint.call("GET", "/s/:shareId").params.map(&.name).should eq(["shareId"])
  end
end
