require "../../func_spec.cr"

home = Endpoint.new("/", "GET").tap do |ep|
  ep.push_callee(Callee.new("HomeService.build", line: 4))
  ep.push_callee(Callee.new("env.redirect", line: 5))
end

users_create = Endpoint.new("/users", "POST", [
  Param.new("user", "", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("env.params.json", line: 9))
  ep.push_callee(Callee.new("UserService.create", line: 10))
end

inline = Endpoint.new("/inline", "GET").tap do |ep|
  ep.push_callee(Callee.new("InlineService.call", line: 14))
end

socket = Endpoint.new("/socket", "GET").tap do |ep|
  ep.push_callee(Callee.new("SocketTracker.connected", line: 18))
  ep.push_callee(Callee.new("socket.send", line: 19))
end

api_user = Endpoint.new("/v1/api/users/:id", "GET").tap do |ep|
  ep.push_callee(Callee.new("env.params.url", line: 25))
  ep.push_callee(Callee.new("UserLookup.find", line: 26))
  ep.push_callee(Callee.new("UserPresenter.render", line: 27))
end

expected_endpoints = [
  home,
  users_create,
  inline,
  socket,
  api_user,
]

FunctionalTester.new("fixtures/crystal/kemal_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("crystal_kemal"),
}).perform_tests
