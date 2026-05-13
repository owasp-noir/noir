require "../../func_spec.cr"

home = Endpoint.new("/lucky/home", "GET").tap do |ep|
  ep.push_callee(Callee.new("HomeService.build", line: 3))
end

users_create = Endpoint.new("/lucky/users", "POST", [
  Param.new("user", "", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("params.from_json", line: 8))
  ep.push_callee(Callee.new("SaveUser.run", line: 9))
  ep.push_callee(Callee.new("AuditTrail.record", line: 10))
  ep.push_callee(Callee.new("UserPresenter.id", line: 11))
end

users_update = Endpoint.new("/lucky/users/:id", "PUT", [
  Param.new("id", "", "query"),
]).tap do |ep|
  ep.push_callee(Callee.new("params.get", line: 16))
  ep.push_callee(Callee.new("UserUpdater.call", line: 17))
end

users_delete = Endpoint.new("/lucky/users/:id", "DELETE").tap do |ep|
  ep.push_callee(Callee.new("UserDestroyer.call", line: 22))
end

users_patch = Endpoint.new("/lucky/users/:id", "PATCH", [
  Param.new("mode", "", "query"),
]).tap do |ep|
  ep.push_callee(Callee.new("UserPatch.apply", line: 27))
end

trace = Endpoint.new("/lucky/trace", "TRACE", [
  Param.new("X-Trace", "", "header"),
]).tap do |ep|
  ep.push_callee(Callee.new("TraceReporter.capture", line: 32))
  ep.push_callee(Callee.new("request.headers", line: 32))
end

socket = Endpoint.new("/lucky/socket", "GET").tap do |ep|
  ep.push_callee(Callee.new("SocketTracker.connected", line: 3))
  ep.push_callee(Callee.new("socket.send", line: 4))
end

expected_endpoints = [
  home,
  users_create,
  users_update,
  users_delete,
  users_patch,
  trace,
  socket,
]

FunctionalTester.new("fixtures/crystal/lucky_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("crystal_lucky"),
}).perform_tests
