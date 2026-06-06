require "../../func_spec.cr"

# Endpoints land with a leading `/` and Noir's optimizer strips
# regex anchors (`^...$`), so the rewritten/regex forms appear with
# the anchor symbols removed.
expected_endpoints = [
  Endpoint.new("/v1/users", "ANY"),
  Endpoint.new("/admin/.*", "ANY"),
  Endpoint.new("/static", "ANY"),
  Endpoint.new("/cgi-bin/", "ANY"),
  Endpoint.new("/backend", "ANY"),
  Endpoint.new("/legacy/(.*)", "ANY"),
  Endpoint.new("/api/(.*)", "ANY"),
]

FunctionalTester.new("fixtures/specification/apache_httpd/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
