require "../../func_spec.cr"

# REST controller index/create/destroy methods invoke a service; assert
# the 1-hop callees surface so the Struts2 callee/ai-context path stays
# covered. `deleteConfirm` exercises the REST-plugin confirm-view action.
orders_index = Endpoint.new("/orders/orders", "GET")
orders_index.push_callee(Callee.new("ordersService.findAll"))
orders_create = Endpoint.new("/orders/orders", "POST")
orders_create.push_callee(Callee.new("ordersService.save"))
orders_destroy = Endpoint.new("/orders/orders/:id", "DELETE", [Param.new("id", "", "path")])
orders_destroy.push_callee(Callee.new("ordersService.deleteById"))

# XML-configured action: callees are resolved from the `<action
# class="…">` handler (DashboardAction#execute) referenced in
# admin-struts.xml, not from a Java-source-discovered route.
admin_dashboard = Endpoint.new("/admin/dashboard", "ANY")
admin_dashboard.push_callee(Callee.new("dashboardService.loadStats"))

expected_endpoints = [
  Endpoint.new("/user/list", "ANY"),
  Endpoint.new("/user/edit", "ANY"),
  Endpoint.new("/user/user_*", "ANY", [Param.new("wildcard", "", "path")]),
  Endpoint.new("/user/audit", "ANY"),
  admin_dashboard,
  Endpoint.new("/admin/reports/*", "ANY", [Param.new("wildcard", "", "path")]),
  Endpoint.new("/admin/users/create", "ANY"),
  Endpoint.new("/admin/users/save", "ANY"),
  Endpoint.new("/products/product", "ANY"),
  orders_index,
  Endpoint.new("/orders/orders/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/orders/orders/:id/deleteConfirm", "GET", [Param.new("id", "", "path")]),
  orders_create,
  Endpoint.new("/orders/orders/:id", "PUT", [Param.new("id", "", "path")]),
  orders_destroy,
  Endpoint.new("/person/list-people", "ANY"),
  Endpoint.new("/annotated/default-annotated", "ANY"),
  Endpoint.new("/multi-a/multi-namespace", "ANY"),
  Endpoint.new("/multi-b/multi-namespace", "ANY"),
]

FunctionalTester.new("fixtures/java/struts2/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {"include_callee" => YAML::Any.new(true)}).perform_tests
