require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/push_audiences", "GET").tap do |ep|
    ep.push_callee(Callee.new("listAudiences", line: 6))
  end,
  Endpoint.new("/push_audiences", "POST").tap do |ep|
    ep.push_callee(Callee.new("parseAudience", line: 8))
    ep.push_callee(Callee.new("AudienceService.create", line: 9))
  end,
]

FunctionalTester.new("fixtures/javascript/express_parse_server_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
