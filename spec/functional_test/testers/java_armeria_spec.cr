require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/graphql", "GET"),
  Endpoint.new("/internal/l7check", "GET"),
  Endpoint.new("/zipkin/config.json", "GET"),
  Endpoint.new("/zipkin/api", "GET"),
  Endpoint.new("/zipkin", "GET"),
  Endpoint.new("/", "GET"),
]

FunctionalTester.new("fixtures/java_armeria/", {
  :techs     => 1,
  :endpoints => 6,
}, extected_endpoints).test_all
