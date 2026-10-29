require "../../func_spec.cr"

# A router builder declared as a method (`h.Register(v1)`, as in the Echo
# RealWorld app) and a free function taking its group as the second argument
# both get the call-site group prefix. Two types sharing a builder method
# name (`(*Admin).Mount`, `(*Billing).Mount`) are ambiguous at their call
# sites, so they keep their bare paths instead of trading prefixes.
expected_endpoints = [
  Endpoint.new("/api/users/login", "POST"),
  Endpoint.new("/api/tags", "GET"),
  Endpoint.new("/admin/stats", "GET"),
  Endpoint.new("/audit", "GET"),
  Endpoint.new("/invoices", "GET"),
]

FunctionalTester.new("fixtures/go/echo_group_method_builder/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
