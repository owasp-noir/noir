require "../../func_spec.cr"

orders_endpoint = Endpoint.new("/api/orders", "GET", [
  Param.new("status", "", "query"),
])
orders_endpoint.push_callee(Callee.new("getQuery", line: 4))
orders_endpoint.push_callee(Callee.new("listOrders", line: 5))
orders_endpoint.push_callee(Callee.new("sendOrders", line: 6))
orders_endpoint.push_callee(Callee.new("serializeOrders", line: 6))

auth_callees = [
  Callee.new("getCookie", line: 4),
  Callee.new("authorizeUser", line: 5),
]

auth_endpoint = Endpoint.new("/auth", "ANY", [
  Param.new("session", "", "cookie"),
]).tap do |ep|
  auth_callees.each { |callee| ep.push_callee(callee) }
end

expected_endpoints = [orders_endpoint, auth_endpoint]

FunctionalTester.new("fixtures/javascript/nuxtjs_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
