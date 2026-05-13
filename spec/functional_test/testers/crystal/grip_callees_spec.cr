require "../../func_spec.cr"

home = Endpoint.new("/api/", "GET").tap do |ep|
  ep.push_callee(Callee.new("HomeService.build", line: 7))
  ep.push_callee(Callee.new("context.json", line: 8))
end

show = Endpoint.new("/api/:id", "GET", [
  Param.new("id", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("context.fetch_path_params", line: 12))
  ep.push_callee(Callee.new("UserLookup.find", line: 13))
  ep.push_callee(Callee.new("UserPresenter.render", line: 14))
  ep.push_callee(Callee.new("context.json", line: 14))
end

create = Endpoint.new("/api/items", "POST").tap do |ep|
  ep.push_callee(Callee.new("PayloadBuilder.from", line: 18))
  ep.push_callee(Callee.new("context.fetch_json_params", line: 18))
  ep.push_callee(Callee.new("ItemService.create", line: 19))
  ep.push_callee(Callee.new("context.put_status", line: 20))
end

status = Endpoint.new("/api/status", "GET").tap do |ep|
  ep.push_callee(Callee.new("ApiStatus.check", line: 38))
  ep.push_callee(Callee.new("context.json", line: 39))
end

health = Endpoint.new("/health", "GET").tap do |ep|
  ep.push_callee(Callee.new("HomeService.build", line: 7))
  ep.push_callee(Callee.new("context.json", line: 8))
end

chat = Endpoint.new("/chat", "GET").tap do |ep|
  ep.push_callee(Callee.new("SocketTracker.connected", line: 28))
  ep.push_callee(Callee.new("context.send", line: 29))
end

expected_endpoints = [
  home,
  show,
  create,
  status,
  health,
  chat,
]

FunctionalTester.new("fixtures/crystal/grip_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("crystal_grip"),
}).perform_tests
