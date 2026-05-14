require "../../func_spec.cr"

def serverpod_endpoint_with_callees(url, params = [] of Param, callees = [] of Callee)
  endpoint = Endpoint.new(url, "POST", params)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

expected_endpoints = [
  serverpod_endpoint_with_callees("/example/hello", [
    Param.new("name", "String", "json"),
  ], [
    Callee.new("UserService.find", line: 6),
    Callee.new("_normalize", line: 7),
    Callee.new("GreetingBuilder.build", line: 8),
  ]),
  serverpod_endpoint_with_callees("/example/ping", [] of Param, [
    Callee.new("Health.check", line: 11),
  ]),
  serverpod_endpoint_with_callees("/order/create", [
    Param.new("order", "Order", "json"),
  ], [
    Callee.new("session.db.insertRow", line: 20),
    Callee.new("AuditLog.write", line: 21),
    Callee.new("OrderDto.fromModel", line: 22),
  ]),
  serverpod_endpoint_with_callees("/chat/subscribe", [
    Param.new("channel", "String", "json"),
  ], [
    Callee.new("Streams.open", line: 28),
  ]),
]

tester = FunctionalTester.new("fixtures/dart/serverpod_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

it "reports the exact Serverpod callees after comments before endpoint classes" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/example/hello" && found.method == "POST" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    expected = expected_endpoints[0].callees.map { |callee| {callee.name, callee.line} }
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(expected)
  end
end
