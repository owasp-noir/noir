require "../../func_spec.cr"

api_loader = Endpoint.new("/api/users", "GET")
api_loader.push_callee(Callee.new("url.searchParams.get", line: 5))
api_loader.push_callee(Callee.new("listUsers", line: 6))
api_loader.push_callee(Callee.new("AuditLog.write", line: 7))
api_loader.push_callee(Callee.new("json", line: 9))
api_loader.push_callee(Callee.new("serializeUsers", line: 9))

api_action_callees = [
  Callee.new("request.json", line: 13),
  Callee.new("serviceFactory().create", line: 14),
  Callee.new("AuditLog.write", line: 15),
  Callee.new("json", line: 17),
]

user_loader = Endpoint.new("/users/{id}", "GET", [
  Param.new("id", "", "path"),
])
user_loader.push_callee(Callee.new("loadUser", line: 4))
user_loader.push_callee(Callee.new("json", line: 5))
user_loader.push_callee(Callee.new("serializeUser", line: 5))

user_action_callees = [
  Callee.new("request.formData", line: 9),
  Callee.new("updateUser", line: 10),
  Callee.new("json", line: 11),
]

expected_endpoints = [
  api_loader,
]

["POST", "PUT", "PATCH", "DELETE"].each do |verb|
  endpoint = Endpoint.new("/api/users", verb)
  api_action_callees.each { |callee| endpoint.push_callee(callee) }
  expected_endpoints << endpoint
end

expected_endpoints << user_loader

["POST", "PUT", "PATCH", "DELETE"].each do |verb|
  endpoint = Endpoint.new("/users/{id}", verb, [
    Param.new("id", "", "path"),
  ])
  user_action_callees.each { |callee| endpoint.push_callee(callee) }
  expected_endpoints << endpoint
end

FunctionalTester.new("fixtures/javascript/remix_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
