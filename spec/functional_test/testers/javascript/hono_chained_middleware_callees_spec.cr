require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/todos", "GET").tap do |ep|
    ep.push_callee(Callee.new("auth.session", line: 26))
    ep.push_callee(Callee.new("todoService().get", line: 27))
    ep.push_callee(Callee.new("c.json", line: 28))
  end,
  Endpoint.new("/todos", "POST").tap do |ep|
    ep.push_callee(Callee.new("c.req.json", line: 31))
    ep.push_callee(Callee.new("auth.session", line: 32))
    ep.push_callee(Callee.new("todoService().add", line: 33))
    ep.push_callee(Callee.new("c.json", line: 34))
  end,
]

FunctionalTester.new("fixtures/javascript/hono_chained_middleware/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
