require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/user/list", "ANY"),
  Endpoint.new("/user/edit", "ANY"),
  Endpoint.new("/user/user_*", "ANY", [Param.new("wildcard", "", "path")]),
  Endpoint.new("/user/audit", "ANY"),
  Endpoint.new("/admin/dashboard", "ANY"),
  Endpoint.new("/admin/reports/*", "ANY", [Param.new("wildcard", "", "path")]),
  Endpoint.new("/admin/users/create", "ANY"),
  Endpoint.new("/admin/users/save", "ANY"),
  Endpoint.new("/products/product", "ANY"),
  Endpoint.new("/orders/orders", "GET"),
  Endpoint.new("/orders/orders/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/orders/orders", "POST"),
  Endpoint.new("/orders/orders/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/orders/orders/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/person/list-people", "ANY"),
  Endpoint.new("/annotated/default-annotated", "ANY"),
  Endpoint.new("/multi-a/multi-namespace", "ANY"),
  Endpoint.new("/multi-b/multi-namespace", "ANY"),
]

FunctionalTester.new("fixtures/java/struts2/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
