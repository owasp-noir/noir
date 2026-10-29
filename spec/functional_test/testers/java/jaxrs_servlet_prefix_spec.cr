require "../../func_spec.cr"

# #3319. Each module is its own base so a module `pom.xml` resolves to the
# module root, as it does when the module is scanned on its own.
# - metrics: `io.dropwizard.metrics` (the Metrics library) in pom.xml is not
#   the Dropwizard framework and must not hide the JAX-RS routes.
# - programmatic: Jersey mounted with `context.addServlet(holder, "/api/*")`.
# - webxml_packages: web.xml servlet with `jersey.config.server.provider.packages`.
# - webxml_appclass: web.xml naming an Application class (`demo.App`) that
#   carries no `@ApplicationPath`.
fixture = "./spec/functional_test/fixtures/java/jaxrs_servlet_prefix"
base_paths = %w[metrics programmatic programmatic_multi webxml_packages webxml_appclass].map { |dir| YAML::Any.new("#{fixture}/#{dir}") }

expected_endpoints = [
  Endpoint.new("/items/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/version", "GET"),
  Endpoint.new("/api/a", "GET"),
  Endpoint.new("/admin/b", "GET"),
  Endpoint.new("/api/v2/version", "GET"),
  Endpoint.new("/api/v3/version", "GET"),
]

FunctionalTester.new("fixtures/java/jaxrs_servlet_prefix/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base" => YAML::Any.new(base_paths),
}).perform_tests
