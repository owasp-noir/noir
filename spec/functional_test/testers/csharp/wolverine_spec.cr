require "../../func_spec.cr"

ship = Endpoint.new("/orders/{id}/ship", "PUT", [
  Param.new("id", "", "path"),
  Param.new("Carrier", "", "json"),
  Param.new("ShipBy", "", "json"),
])
ship.push_callee(Callee.new("bus.PublishAsync", line: 25))

expected_endpoints = [
  Endpoint.new("/orders", "POST", [
    Param.new("Customer", "", "json"),
    Param.new("Total", "", "json"),
    Param.new("Items", "", "json"),
  ]),
  Endpoint.new("/orders/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/orders", "GET", [
    Param.new("customer", "", "query"),
    Param.new("page", "", "query"),
    Param.new("X-Tenant", "", "header"),
  ]),
  ship,
  Endpoint.new("/orders/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/orders/{id}/note", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("reason", "", "query"),
    Param.new("patch", "", "json"),
  ]),
  Endpoint.new("/status", "HEAD"),
]

# The csproj also trips cs_aspnet_core_mvc (Web SDK); it must add nothing.
# The commented-out route and the tests/ file are not endpoints.
FunctionalTester.new("fixtures/csharp/wolverine/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
