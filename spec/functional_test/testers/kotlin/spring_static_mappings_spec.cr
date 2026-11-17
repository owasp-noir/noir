require "../../func_spec.cr"

# An `@EnableWebMvc` configuration that registers `/**` over
# `classpath:/static/` itself: `static/` stays served through that handler,
# `public/` is no longer a static location, and the location built from an
# injected property is unknown.
expected_endpoints = [
  Endpoint.new("/robots.txt", "GET"),
]

tester = FunctionalTester.new("fixtures/kotlin/spring_static_mappings/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests
