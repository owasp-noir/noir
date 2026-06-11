require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/items/:id", "GET").tap do |ep|
    ep.push_callee(Callee.new("c.req.param", line: 10))
    ep.push_callee(Callee.new("c.json", line: 11))
    ep.push_callee(Callee.new("itemService.lookup", line: 11))
  end,
  Endpoint.new("/items/:id", "POST").tap do |ep|
    ep.push_callee(Callee.new("c.req.param", line: 10))
    ep.push_callee(Callee.new("c.json", line: 11))
    ep.push_callee(Callee.new("itemService.lookup", line: 11))
  end,
  Endpoint.new("/users/:userId", "PUT").tap do |ep|
    ep.push_callee(Callee.new("c.req.param", line: 16))
    ep.push_callee(Callee.new("c.json", line: 17))
    ep.push_callee(Callee.new("UserService.update", line: 17))
  end,
  Endpoint.new("/users/:userId", "PATCH").tap do |ep|
    ep.push_callee(Callee.new("c.req.param", line: 16))
    ep.push_callee(Callee.new("c.json", line: 17))
    ep.push_callee(Callee.new("UserService.update", line: 17))
  end,
]

FunctionalTester.new("fixtures/javascript/hono_on_array/", {
  :techs => 1,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
