require "../../func_spec.cr"

# Kotlin side of the Spring framework-provided routes (#3092, #3093):
# Actuator from a `build.gradle.kts` dependency (springdoc is commented out,
# so it is not), `exposure.include: ["*"]` minus `exclude` and a disabled
# endpoint under a custom base path; the Kotlin Security DSL; and a dotfile
# under the default `static/` location.
core = %w[beans caches conditions configprops health loggers mappings metrics scheduledtasks threaddump]

expected_endpoints = [
  Endpoint.new("/ping", "GET"),
  Endpoint.new("/.env", "GET"),
  Endpoint.new("/mgmt", "GET"),
] + core.map { |id| Endpoint.new("/mgmt/#{id}", "GET") } + [
  # No `loginProcessingUrl`: the filter listens on the login page URL.
  Endpoint.new("/auth/login", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
  ]),
  Endpoint.new("/bye", "POST"),
  Endpoint.new("/oauth/start/{registrationId}", "GET"),
  Endpoint.new("/login/oauth2/code/{registrationId}", "GET", [
    Param.new("code", "", "query"),
    Param.new("state", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/kotlin/spring_provided_routes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
