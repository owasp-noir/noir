require "../../func_spec.cr"

show_endpoint = Endpoint.new("/api/Orders/{id}", "GET", [
  Param.new("id", "", "path"),
])
show_endpoint.push_callee(Callee.new("orderService.Load", line: 12))
show_endpoint.push_callee(Callee.new("AuditLog.Write", line: 13))
show_endpoint.push_callee(Callee.new("Ok", line: 14))
show_endpoint.push_callee(Callee.new("SerializeOrder", line: 14))

create_endpoint = Endpoint.new("/api/Orders", "POST", [
  Param.new("name", "", "json"),
])
create_endpoint.push_callee(Callee.new("orderService.Create", line: 20))
create_endpoint.push_callee(Callee.new("Created", line: 21))
create_endpoint.push_callee(Callee.new("SerializeOrder", line: 21))

mapped_endpoint = Endpoint.new("/mapped/orders/{id}", "POST", [
  Param.new("id", "", "path"),
  Param.new("expand", "", "query"),
])
mapped_endpoint.push_callee(Callee.new("orderService.Save", line: 13))
mapped_endpoint.push_callee(Callee.new("AuditLog.Write", line: 14))
mapped_endpoint.push_callee(Callee.new("context.Response.WriteAsync", line: 15))
mapped_endpoint.push_callee(Callee.new("SerializeOrder", line: 15))

FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_callees/", {
  :techs     => 2,
  :endpoints => 3,
}, [
  show_endpoint,
  create_endpoint,
  mapped_endpoint,
], {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
