require "../../func_spec.cr"

# `use_doorkeeper do ... end` generates Doorkeeper's OAuth2 routes.
# This fixture exercises `skip_controllers` (drops the applications and
# authorized_applications resources) and the `controllers` remap (token
# endpoints resolve to the app's own `oauth/tokens` controller, so
# params and callees attach).
token_endpoint = Endpoint.new("/oauth/token", "POST", [
  Param.new("grant_type", "", "form"),
]).tap do |ep|
  ep.push_callee(Callee.new("AuditLog.write"))
end

revoke_endpoint = Endpoint.new("/oauth/revoke", "POST", [
  Param.new("token", "", "form"),
]).tap do |ep|
  ep.push_callee(Callee.new("TokenRevoker.revoke"))
end

expected_endpoints = [
  Endpoint.new("/oauth/authorize", "GET"),
  Endpoint.new("/oauth/authorize", "POST"),
  Endpoint.new("/oauth/authorize", "DELETE"),
  token_endpoint,
  revoke_endpoint,
  Endpoint.new("/oauth/introspect", "POST"),
  Endpoint.new("/oauth/token/info", "GET"),
]

FunctionalTester.new("fixtures/ruby/rails_doorkeeper/", {
  :techs     => 1,
  :endpoints => 7,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
