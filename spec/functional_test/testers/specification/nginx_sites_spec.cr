require "../../func_spec.cr"

# Debian's extension-less `sites-available/<name>` vhost and an Ansible
# `.conf.j2` template.
expected_endpoints = [
  Endpoint.new("/api/", "ANY"),
  Endpoint.new("/j2-api/", "ANY"),
]

FunctionalTester.new("fixtures/specification/nginx_sites/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
