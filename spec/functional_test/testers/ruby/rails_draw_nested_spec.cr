require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/admin/accounts", "GET"),
  Endpoint.new("/admin/accounts/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/about", "GET"),
  Endpoint.new("/loop/once", "GET"),
  Endpoint.new("/admin/reports", "GET"),
]

FunctionalTester.new("fixtures/ruby/rails_draw_nested/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
