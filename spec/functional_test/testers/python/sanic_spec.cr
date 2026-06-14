require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/sign", "GET"),
  Endpoint.new("/sign", "POST", [Param.new("username", "", "form"), Param.new("password", "", "form")]),
  Endpoint.new("/cookie", "GET", [Param.new("test", "", "cookie")]),
  Endpoint.new("/login", "POST", [Param.new("username", "", "form"), Param.new("password", "", "form")]),
  Endpoint.new("/create_record", "PUT", [Param.new("name", "", "form")]),
  Endpoint.new("/delete_record", "DELETE", [Param.new("name", "", "json")]),
  Endpoint.new("/get_ip", "GET"),
  Endpoint.new("/", "GET"),
  Endpoint.new("/feed/{channel}", "GET", [
    Param.new("channel", "", "path"),
    Param.new("token", "", "query"),
  ]),
  Endpoint.new("/api/v1/reports/{report_id}", "GET", [
    Param.new("report_id", "", "path"),
    Param.new("include", "", "query"),
  ]),
  Endpoint.new("/api/v1/reports/create", "POST", [Param.new("title", "", "json")]),
  Endpoint.new("/reports/{report_id}/status", "PATCH", [
    Param.new("status", "", "json"),
    Param.new("report_id", "", "path"),
  ]),
  Endpoint.new("/api/v1/reports/audit", "GET", [
    Param.new("actor", "", "query"),
  ]),
  Endpoint.new("/class-reports/{report_id}", "GET", [
    Param.new("report_id", "", "path"),
    Param.new("include", "", "query"),
  ]),
  Endpoint.new("/class-reports/{report_id}", "POST", [
    Param.new("report_id", "", "path"),
    Param.new("title", "", "json"),
  ]),
  Endpoint.new("/external/{item_id}", "PUT", [
    Param.new("item_id", "", "path"),
    Param.new("trace", "", "query"),
    Param.new("state", "", "json"),
  ]),
  Endpoint.new("/assets/*", "GET"),
  Endpoint.new("/api/v1/reports/files/*", "GET"),
  # Blueprint.group(url_prefix="/admin-api", version=2): /v<version> is
  # outermost, then the group prefix, then each blueprint's url_prefix. A
  # route-level version= (the /ping route) overrides just that route.
  Endpoint.new("/v2/admin-api/admin/users", "GET"),
  Endpoint.new("/v2/admin-api/metrics/health", "GET"),
  Endpoint.new("/v3/admin-api/metrics/ping", "GET"),
  Endpoint.new("/programmatic-feed/{channel}", "GET", [
    Param.new("channel", "", "path"),
    Param.new("token", "", "query"),
  ]).tap do |endpoint|
    endpoint.protocol = "ws"
  end,
]

tester = FunctionalTester.new("fixtures/python/sanic/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "marks Sanic websocket endpoints with ws protocol" do
  feed = tester.app.endpoints.find { |endpoint| endpoint.url == "/feed/{channel}" }
  feed.should_not be_nil
  feed.try(&.protocol).should eq("ws")
end
