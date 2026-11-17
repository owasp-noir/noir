require "../../func_spec.cr"

# A module whose build disables the Boot application archive
# (`bootJar { enabled = false }`, Kotlin DSL `tasks.getByName<BootJar>`) is a
# library: it serves nothing itself, so its actuator and springdoc
# dependencies add no rows. The application module keeps its own (actuator
# on a management port with base path `/`), and so does a WAR application
# that disables bootJar because it ships `bootWar` instead.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/war-ping", "GET"),
  Endpoint.new("/war-actuator", "GET"),
  Endpoint.new("/war-actuator/health", "GET"),
]

tester = FunctionalTester.new("fixtures/java/spring_library_module/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Spring library modules", tags: "functional" do
  it "report no framework rows of their own" do
    urls = tester.endpoints.map(&.url)
    {"/actuator", "/actuator/health", "/v3/api-docs", "/swagger-ui.html", "/kts-lib-actuator"}.each do |url|
      urls.should_not contain(url)
    end
  end
end
