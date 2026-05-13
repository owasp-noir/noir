require "../../func_spec.cr"

details_endpoint = Endpoint.new("/Shop/Details", "GET", [
  Param.new("id", "", "query"),
])
details_endpoint.push_callee(Callee.new("shopService.Load", line: 9))
details_endpoint.push_callee(Callee.new("AuditLog.Write", line: 10))
details_endpoint.push_callee(Callee.new("View", line: 11))
details_endpoint.push_callee(Callee.new("SerializeItem", line: 11))

create_endpoint = Endpoint.new("/Shop/Create", "POST", [
  Param.new("name", "", "form"),
  Param.new("email", "", "form"),
])
create_endpoint.push_callee(Callee.new("shopService.Create", line: 17))
create_endpoint.push_callee(Callee.new("Json", line: 18))
create_endpoint.push_callee(Callee.new("SerializeItem", line: 18))

FunctionalTester.new("fixtures/csharp/aspnet_mvc_callees/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  details_endpoint,
  create_endpoint,
], {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
