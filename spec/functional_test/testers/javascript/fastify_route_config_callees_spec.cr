require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/single", "GET").tap do |ep|
    ep.push_callee(Callee.new("reply.send", line: 8))
    ep.push_callee(Callee.new("statusService.single", line: 8))
  end,
  Endpoint.new("/items/:id", "GET", [Param.new("id", "", "path")]).tap do |ep|
    ep.push_callee(Callee.new("reply.send", line: 17))
    ep.push_callee(Callee.new("buildItem", line: 17))
  end,
  Endpoint.new("/items/:id", "POST", [Param.new("id", "", "path")]).tap do |ep|
    ep.push_callee(Callee.new("reply.send", line: 17))
    ep.push_callee(Callee.new("buildItem", line: 17))
  end,
  Endpoint.new("/users/:userId", "PUT", [
    Param.new("email", "", "json"),
    Param.new("userId", "", "path"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("reply.send", line: 28))
    ep.push_callee(Callee.new("UserService.update", line: 28))
  end,
  Endpoint.new("/users/:userId", "PATCH", [
    Param.new("email", "", "json"),
    Param.new("userId", "", "path"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("reply.send", line: 28))
    ep.push_callee(Callee.new("UserService.update", line: 28))
  end,
]

FunctionalTester.new("fixtures/javascript/fastify_route_config/", {
  :techs => 1,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
