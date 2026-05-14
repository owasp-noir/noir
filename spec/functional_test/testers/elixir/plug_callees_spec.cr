require "../../func_spec.cr"

users_index = Endpoint.new("/users", "GET", [
  Param.new("page", "", "query"),
]).tap do |ep|
  ep.push_callee(Callee.new("UserService.list", line: 9))
  ep.push_callee(Callee.new("AuditLog.write", line: 10))
  ep.push_callee(Callee.new("JsonPresenter.render", line: 11))
  ep.push_callee(Callee.new("send_resp", line: 11))
end

users_create = Endpoint.new("/users", "POST").tap do |ep|
  ep.push_callee(Callee.new("UserPayload.from_conn", line: 15))
  ep.push_callee(Callee.new("UserService.create", line: 16))
  ep.push_callee(Callee.new("send_resp", line: 17))
  ep.push_callee(Callee.new("render_user", line: 17))
end

health = Endpoint.new("/health", "GET").tap do |ep|
  ep.push_callee(Callee.new("Health.ready?", line: 21))
end

webhook_post = Endpoint.new("/webhook", "POST").tap do |ep|
  ep.push_callee(Callee.new("WebhookHandler.dispatch", line: 29))
  ep.push_callee(Callee.new("send_resp", line: 30))
end

webhook_put = Endpoint.new("/webhook", "PUT").tap do |ep|
  ep.push_callee(Callee.new("WebhookHandler.dispatch", line: 29))
  ep.push_callee(Callee.new("send_resp", line: 30))
end

expected_endpoints = [
  users_index,
  users_create,
  health,
  webhook_post,
  webhook_put,
]

FunctionalTester.new("fixtures/elixir/plug_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("elixir_plug"),
}).perform_tests
