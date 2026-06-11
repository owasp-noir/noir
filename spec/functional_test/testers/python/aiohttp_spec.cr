require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "GET", [
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
  ]),
  Endpoint.new("/users/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("role", "", "form"),
  ]),
  Endpoint.new("/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/{id}", "PATCH", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/alias/{alias_id}", "GET", [
    Param.new("alias_id", "", "path"),
  ]),
  Endpoint.new("/wildcard", "GET"),
  Endpoint.new("/wildcard", "POST"),
  Endpoint.new("/wildcard", "PUT"),
  Endpoint.new("/wildcard", "DELETE"),
  Endpoint.new("/wildcard", "PATCH"),
  Endpoint.new("/wildcard", "HEAD"),
  Endpoint.new("/wildcard", "OPTIONS"),
  Endpoint.new("/feed/{channel}", "GET", [
    Param.new("channel", "", "path"),
    Param.new("token", "", "query"),
  ]),
  Endpoint.new("/reports/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("verbose", "", "query"),
  ]),
  Endpoint.new("/reports/{id}", "POST", [
    Param.new("id", "", "path"),
    Param.new("title", "", "json"),
  ]),
  Endpoint.new("/assets/*", "GET"),
  Endpoint.new("/decorated/{item_id}", "GET", [
    Param.new("item_id", "", "path"),
  ]),
  Endpoint.new("/decorated/{item_id}", "PATCH", [
    Param.new("item_id", "", "path"),
    Param.new("status", "", "json"),
  ]),
  Endpoint.new("/admin", "GET", [
    Param.new("session", "", "cookie"),
    Param.new("User-Agent", "", "header"),
  ]),
  Endpoint.new("/login", "POST", [
    Param.new("username", "", "json"),
    Param.new("password", "", "json"),
  ]),
  Endpoint.new("/profile", "PUT", [
    Param.new("bio", "", "form"),
  ]),
  Endpoint.new("/search/{category}", "GET", [
    Param.new("category", "", "path"),
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/admin/stats", "GET", [
    Param.new("section", "", "query"),
  ]),
  Endpoint.new("/admin/health/{check}", "GET", [
    Param.new("check", "", "path"),
  ]),
  Endpoint.new("/admin/audit/{audit_id}", "GET", [
    Param.new("audit_id", "", "path"),
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/admin/audit/{audit_id}", "DELETE", [
    Param.new("audit_id", "", "path"),
    Param.new("X-Audit-Token", "", "header"),
  ]),
  Endpoint.new("/admin/static/*", "GET"),
  Endpoint.new("/tenant-api/tenants/{tenant_id}", "GET", [
    Param.new("tenant_id", "", "path"),
    Param.new("expand", "", "query"),
  ]),
  Endpoint.new("/tenant-api/tenants", "POST", [
    Param.new("name", "", "json"),
  ]),
  Endpoint.new("/tenant-api/external/{external_id}", "PATCH", [
    Param.new("external_id", "", "path"),
    Param.new("mode", "", "query"),
    Param.new("title", "", "json"),
  ]),
]

tester = FunctionalTester.new("fixtures/python/aiohttp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "marks aiohttp WebSocketResponse handlers with ws protocol" do
  feed = tester.app.endpoints.find { |endpoint| endpoint.url == "/feed/{channel}" }
  feed.should_not be_nil
  feed.try(&.protocol).should eq("ws")
end
