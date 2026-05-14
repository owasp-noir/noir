require "../../func_spec.cr"

list_endpoint = Endpoint.new("/users", "GET")
list_endpoint.push_callee(Callee.new("UserService.list", line: 16))
list_endpoint.push_callee(Callee.new("complete", line: 17))
list_endpoint.push_callee(Callee.new("renderUsers", line: 17))

create_endpoint = Endpoint.new("/users", "POST", [Param.new("body", "User", "json")])
create_endpoint.push_callee(Callee.new("entity", line: 20))
create_endpoint.push_callee(Callee.new("UserService.create", line: 21))
create_endpoint.push_callee(Callee.new("AuditLog.write", line: 22))
create_endpoint.push_callee(Callee.new("complete", line: 23))
create_endpoint.push_callee(Callee.new("renderUser", line: 23))

show_item_endpoint = Endpoint.new("/api/v1/items/{itemId}", "GET", [Param.new("itemId", "", "path")])
show_item_endpoint.push_callee(Callee.new("ItemService.find", line: 35))
show_item_endpoint.push_callee(Callee.new("complete", line: 36))
show_item_endpoint.push_callee(Callee.new("renderItem", line: 36))

update_item_endpoint = Endpoint.new("/api/v1/items/{itemId}", "PUT", [
  Param.new("itemId", "", "path"),
  Param.new("body", "Item", "json"),
  Param.new("Authorization", "", "header"),
])
update_item_endpoint.push_callee(Callee.new("entity", line: 39))
update_item_endpoint.push_callee(Callee.new("headerValueByName", line: 40))
update_item_endpoint.push_callee(Callee.new("ItemService.update", line: 41))
update_item_endpoint.push_callee(Callee.new("complete", line: 42))
update_item_endpoint.push_callee(Callee.new("renderItem", line: 42))

delete_item_endpoint = Endpoint.new("/api/v1/items/{itemId}", "DELETE", [
  Param.new("itemId", "", "path"),
  Param.new("X-API-Key", "", "header"),
])
delete_item_endpoint.push_callee(Callee.new("optionalHeaderValueByName", line: 47))
delete_item_endpoint.push_callee(Callee.new("ItemService.delete", line: 48))
delete_item_endpoint.push_callee(Callee.new("complete", line: 49))

compact_endpoint = Endpoint.new("/compact", "GET")
compact_endpoint.push_callee(Callee.new("complete", line: 57))
compact_endpoint.push_callee(Callee.new("HealthService.check", line: 57))

multi_endpoint = Endpoint.new("/multi", "GET")
multi_endpoint.push_callee(Callee.new("FirstService.call", line: 63))
multi_endpoint.push_callee(Callee.new("SecondService.call", line: 67))

expected_endpoints = [
  list_endpoint,
  create_endpoint,
  show_item_endpoint,
  update_item_endpoint,
  delete_item_endpoint,
  compact_endpoint,
  multi_endpoint,
]

FunctionalTester.new("fixtures/scala/akka_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
