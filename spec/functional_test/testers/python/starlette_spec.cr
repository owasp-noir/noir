require "../../func_spec.cr"

submit_params = [
  Param.new("body", "", "json"),
  Param.new("name", "", "query"),
  Param.new("X-Token", "", "header"),
  Param.new("session", "", "cookie"),
]

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users/{user_id}", "GET", [Param.new("user_id", "", "path")]),
  Endpoint.new("/submit", "GET", submit_params),
  Endpoint.new("/submit", "POST", submit_params),
  Endpoint.new("/search", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/upload", "POST", [Param.new("body", "", "form")]),
  Endpoint.new("/profile/{name}", "GET", [Param.new("name", "", "path")]),
  Endpoint.new("/external/{item_id}", "GET", [
    Param.new("item_id", "", "path"),
    Param.new("q", "", "query"),
    Param.new("title", "", "json"),
  ]),
  Endpoint.new("/reports/{report_id}", "GET", [
    Param.new("report_id", "", "path"),
    Param.new("include", "", "query"),
  ]),
  Endpoint.new("/reports/{report_id}", "POST", [
    Param.new("report_id", "", "path"),
    Param.new("title", "", "json"),
  ]),
  Endpoint.new("/api/items", "GET"),
  Endpoint.new("/api/items/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/admin/dashboard", "GET", [Param.new("section", "", "query")]),
  Endpoint.new("/admin/reports/{report_id}", "GET", [
    Param.new("report_id", "", "path"),
    Param.new("include", "", "query"),
  ]),
  Endpoint.new("/admin/reports/{report_id}", "POST", [
    Param.new("report_id", "", "path"),
    Param.new("title", "", "json"),
  ]),
  Endpoint.new("/internal/status", "GET", [
    Param.new("region", "", "query"),
  ]),
  Endpoint.new("/accounts/overview", "GET", [
    Param.new("region", "", "query"),
  ]),
  Endpoint.new("/accounts/billing/invoices", "GET"),
  Endpoint.new("/nested/v1/metrics/{metric_id}", "GET", [
    Param.new("metric_id", "", "path"),
    Param.new("window", "", "query"),
  ]),
  Endpoint.new("/programmatic/audit/{entry_id}", "GET", [
    Param.new("entry_id", "", "path"),
    Param.new("source", "", "query"),
  ]),
  Endpoint.new("/programmatic/ws/{room}", "GET", [
    Param.new("room", "", "path"),
    Param.new("token", "", "query"),
  ]),
  Endpoint.new("/assets/*", "GET"),
  Endpoint.new("/ws/{room}", "GET", [
    Param.new("room", "", "path"),
    Param.new("token", "", "query"),
  ]),
  Endpoint.new("/notifications/{topic}", "GET", [
    Param.new("topic", "", "path"),
    Param.new("X-Client", "", "header"),
  ]),
]

tester = FunctionalTester.new("fixtures/python/starlette/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "marks Starlette WebSocketRoute endpoints with ws protocol" do
  chat = tester.app.endpoints.find { |endpoint| endpoint.url == "/ws/{room}" }
  chat.should_not be_nil
  chat.try(&.protocol).should eq("ws")

  notifications = tester.app.endpoints.find { |endpoint| endpoint.url == "/notifications/{topic}" }
  notifications.should_not be_nil
  notifications.try(&.protocol).should eq("ws")

  programmatic = tester.app.endpoints.find { |endpoint| endpoint.url == "/programmatic/ws/{room}" }
  programmatic.should_not be_nil
  programmatic.try(&.protocol).should eq("ws")
end
