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
admin_dashboard_refresh = Endpoint.new("/admin/dashboard-refresh", "ANY")
admin_dashboard_refresh.push_callee(Callee.new("dashboardService.refreshStats"))

expected_endpoints = [
  Endpoint.new("/user/list", "ANY"),
  Endpoint.new("/user/edit", "ANY"),
  Endpoint.new("/user/user_*", "ANY", [Param.new("wildcard", "", "path")]),
  Endpoint.new("/user/audit", "ANY"),
  admin_dashboard,
  admin_dashboard_refresh,
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
  Endpoint.new("/commented/list", "ANY"),
  Endpoint.new("/commented/own", "ANY"),
]

FunctionalTester.new("fixtures/java/struts2/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {"include_callee" => YAML::Any.new(true)}).perform_tests

describe "Struts2 line numbers", tags: "functional" do
  # CommentedAction.java holds a multi-byte string literal inside the class (comments
  # are blanked to ASCII before scanning, so they would not exercise this), so a
  # char/byte mix-up in the per-file offset index shifts these lines.
  it "keeps method lines after non-ASCII text" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/java/struts2/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    app.endpoints.find!(&.url.==("/commented/list")).details.code_paths.first.line.should eq(13)
    app.endpoints.find!(&.url.==("/commented/own")).details.code_paths.first.line.should eq(18)
  end
end
