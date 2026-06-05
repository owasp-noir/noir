require "../../func_spec.cr"

app_root = Endpoint.new("/", "ANY")
app_root.protocol = "https"

healthcheck = Endpoint.new("/healthz", "GET")
healthcheck.protocol = "https"

expected_endpoints = [
  app_root,
  healthcheck,
]

FunctionalTester.new("fixtures/specification/kamal/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
