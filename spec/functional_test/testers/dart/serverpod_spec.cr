require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/example/hello", "POST", [
    Param.new("name", "String", "json"),
  ]),
  Endpoint.new("/example/add", "POST", [
    Param.new("a", "int", "json"),
    Param.new("b", "int", "json"),
  ]),
  Endpoint.new("/order/list", "POST", [
    Param.new("limit", "int", "json"),
    Param.new("cursor", "String?", "json"),
  ]),
  Endpoint.new("/order/create", "POST", [
    Param.new("order", "Order", "json"),
  ]),
  Endpoint.new("/health/ping", "POST"),

  # Web-server routes registered via `pod.webServer.addRoute(...)`.
  # `RootRoute` (a WidgetRoute) defaults to GET and is mounted at two
  # paths; `WebhookRoute` declares `methods: {Method.post}`. The
  # `RouteStaticDirectory` registration is skipped (static file serving),
  # and the `test/integration` helper is ignored.
  Endpoint.new("/", "GET"),
  Endpoint.new("/index.html", "GET"),
  Endpoint.new("/webhook", "POST"),
]

serverpod_tester = FunctionalTester.new("fixtures/dart/serverpod/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
serverpod_tester.perform_tests

it "extracts callees from a Serverpod web-route handler body" do
  endpoint = serverpod_tester.app.endpoints.find { |found| found.url == "/webhook" && found.method == "POST" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map(&.name).should contain("processWebhook")
  end
end
