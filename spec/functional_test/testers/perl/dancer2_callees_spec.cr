require "../../func_spec.cr"

def dancer2_endpoint_with_callees(url, method, params = [] of Param, callees = [] of Callee)
  endpoint = Endpoint.new(url, method, params)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

hello_callees = [
  Callee.new("GreetingService::build", line: 5),
  Callee.new("Audit.log", line: 6),
  Callee.new("template", line: 7),
]

status_callees = [
  Callee.new("StatusService.current", line: 14),
  Callee.new("to_json", line: 15),
]

login_callees = [
  Callee.new("body_parameters.get", line: 22),
  Callee.new("LoginService::authenticate", line: 23),
  Callee.new("to_json", line: 24),
]

expected_endpoints = [
  dancer2_endpoint_with_callees("/hello", "GET", [] of Param, hello_callees),
  dancer2_endpoint_with_callees("/status", "GET", [] of Param, status_callees),
  dancer2_endpoint_with_callees("/api/login", "POST", [
    Param.new("username", "", "form"),
  ], login_callees),
]

tester = FunctionalTester.new("fixtures/perl/dancer2_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

it "reports exact Dancer2 inline-handler callees" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/hello" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(hello_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "resolves Dancer2 code-ref (`=> \\&handler`) callees via the named-sub index" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/status" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(status_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "attaches callees to prefix-nested Dancer2 routes" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/api/login" && found.method == "POST" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(login_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "populates Dancer2 callee source paths" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/hello" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    paths = actual.callees.map(&.path)
    paths.uniq!
    paths.should eq([
      "./spec/functional_test/fixtures/perl/dancer2_callees/lib/MyApp.pm",
    ])
  end
end

it "does not populate Dancer2 callees by default" do
  config_init = ConfigInitializer.new
  noir_options = config_init.default_options
  noir_options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/perl/dancer2_callees/")])
  noir_options["nolog"] = YAML::Any.new(true)

  app = NoirRunner.new(noir_options)
  app.detect
  app.analyze
  app.endpoints.should_not be_empty
  app.endpoints.each do |endpoint|
    endpoint.callees.should be_empty
  end
end
