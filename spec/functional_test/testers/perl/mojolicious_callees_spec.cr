require "../../func_spec.cr"

def mojolicious_endpoint_with_callees(url, method, params = [] of Param, callees = [] of Callee, protocol = "http")
  endpoint = Endpoint.new(url, method, params)
  endpoint.protocol = protocol
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

hello_callees = [
  Callee.new("GreetingService::build", line: 5),
  Callee.new("c.param", line: 5),
  Callee.new("Audit.log", line: 6),
  Callee.new("c.render", line: 7),
]

inline_callees = [
  Callee.new("InlineService::call", line: 10),
  Callee.new("c.render", line: 10),
]

multi_callees = [
  Callee.new("MultiService.load", line: 13),
  Callee.new("c.render", line: 14),
]

echo_callees = [
  Callee.new("c.on", line: 18),
  Callee.new("EchoService::accepted", line: 19),
]

status_callees = [
  Callee.new("StatusService.current", line: 5),
  Callee.new("c.render", line: 6),
]

login_callees = [
  Callee.new("LoginService::authenticate", line: 10),
  Callee.new("c.param", line: 10),
  Callee.new("c.render", line: 11),
]

admin_show_callees = [
  Callee.new("Admin.UserService.find", line: 5),
  Callee.new("c.param", line: 5),
  Callee.new("c.render", line: 6),
]

admin_create_callees = [
  Callee.new("Admin.UserService.create", line: 10),
  Callee.new("c.param", line: 10),
  Callee.new("c.render", line: 11),
]

expected_endpoints = [
  mojolicious_endpoint_with_callees("/hello", "GET", [
    Param.new("name", "", "query"),
  ], hello_callees),
  mojolicious_endpoint_with_callees("/inline", "GET", [] of Param, inline_callees),
  mojolicious_endpoint_with_callees("/multi", "GET", [] of Param, multi_callees),
  mojolicious_endpoint_with_callees("/multi", "POST", [] of Param, multi_callees),
  mojolicious_endpoint_with_callees("/echo", "GET", [] of Param, echo_callees, "ws"),
  mojolicious_endpoint_with_callees("/api/status", "GET", [] of Param, status_callees),
  mojolicious_endpoint_with_callees("/api/login", "POST", [] of Param, login_callees),
  mojolicious_endpoint_with_callees("/admin/users/:id", "GET", [
    Param.new("id", "", "path"),
  ], admin_show_callees),
  mojolicious_endpoint_with_callees("/admin/users", "POST", [] of Param, admin_create_callees),
]

tester = FunctionalTester.new("fixtures/perl/mojolicious_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

it "reports exact Mojolicious::Lite callees for inline handlers" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/hello" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(hello_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "reuses Mojolicious any-handler callees for every emitted method" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/multi" && found.method == "POST" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(multi_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "keeps nested websocket callback callees out of the route body" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/echo" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(echo_callees.map { |callee| {callee.name, callee.line} })
    actual.callees.map(&.name).should_not contain("HiddenService::nested")
    actual.callees.map(&.name).should_not contain("c.send")
  end
end

it "attaches Mojolicious full-app controller action callees" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/api/login" && found.method == "POST" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(login_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "attaches nested Mojolicious controller action callees" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/admin/users/:id" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(admin_show_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "attaches named Mojolicious controller/action callees" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/admin/users" && found.method == "POST" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(admin_create_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "populates Mojolicious callee source paths" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/api/status" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    paths = actual.callees.map(&.path)
    paths.uniq!
    paths.should eq([
      "./spec/functional_test/fixtures/perl/mojolicious_callees/lib/MyApp/Controller/Api.pm",
    ])
  end
end

it "does not populate Mojolicious callees by default" do
  config_init = ConfigInitializer.new
  noir_options = config_init.default_options
  noir_options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/perl/mojolicious_callees/")])
  noir_options["nolog"] = YAML::Any.new(true)

  app = NoirRunner.new(noir_options)
  app.detect
  app.analyze
  app.endpoints.should_not be_empty
  app.endpoints.each do |endpoint|
    endpoint.callees.should be_empty
  end
end
