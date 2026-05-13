require "../../func_spec.cr"

list_callees = [
  Callee.new("getQuery", line: 2),
  Callee.new("listUsers", line: 3),
  Callee.new("AuditLog.write", line: 4),
  Callee.new("sendUsers", line: 6),
  Callee.new("serializeUsers", line: 6),
]

create_callees = [
  Callee.new("readBody", line: 2),
  Callee.new("serviceFactory().create", line: 3),
  Callee.new("AuditLog.write", line: 4),
  Callee.new("sendUser", line: 6),
]

expected_endpoints = ["GET", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"].map do |method|
  Endpoint.new("/users", method, [
    Param.new("page", "", "query"),
  ]).tap do |ep|
    list_callees.each { |callee| ep.push_callee(callee) }
  end
end

expected_endpoints << Endpoint.new("/users", "POST").tap do |ep|
  create_callees.each { |callee| ep.push_callee(callee) }
end

FunctionalTester.new("fixtures/javascript/nitro_callees/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
