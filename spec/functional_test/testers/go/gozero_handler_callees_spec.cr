require "../../func_spec.cr"

# `AddRoutes` rows get the handler factory's 1-hop callees, and
# `httpx.Parse(r, &req)` reads `req`'s tagged fields.
expected_endpoints = [
  Endpoint.new("/run", "POST", [Param.new("cmd", "", "json")]).tap do |ep|
    ep.push_callee(Callee.new("httpx.Parse"))
    ep.push_callee(Callee.new("logic.NewRunLogic"))
    ep.push_callee(Callee.new("l.Run"))
  end,
  # goctl's multi-line `{\n Method: ...,\n Handler: h,\n}` form.
  Endpoint.new("/run2", "POST", [Param.new("cmd", "", "json")]).tap do |ep|
    ep.push_callee(Callee.new("logic.NewRunLogic"))
    ep.push_callee(Callee.new("l.Run"))
  end,
]

FunctionalTester.new("fixtures/go/gozero_handler_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
