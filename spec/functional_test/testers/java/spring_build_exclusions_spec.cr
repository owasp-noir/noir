require "../../func_spec.cr"

# An exclusion is not a dependency: Gradle `exclude group:, module:` (Groovy)
# and `exclude(group =, module =)` (Kotlin DSL), Maven `<exclusions>`. A
# module that excludes an artifact from all its configurations does not get
# it from the parent's `subprojects {}` either; a sibling that does not
# exclude it still does (`/docs`), even when its own `subprojects {}` (which
# configures other modules) or the root's `project(':kts') {}` excludes it.
expected_endpoints = [
  Endpoint.new("/app-ping", "GET"),
  Endpoint.new("/kts-ping", "GET"),
  Endpoint.new("/maven-ping", "GET"),
  Endpoint.new("/docs/docs-ping", "GET"),
  Endpoint.new("/docs/v3/api-docs", "GET"),
  Endpoint.new("/docs/swagger-ui.html", "GET"),
]

tester = FunctionalTester.new("fixtures/java/spring_build_exclusions/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Spring build exclusions", tags: "functional" do
  it "reports no actuator or springdoc row for an excluded artifact" do
    urls = tester.endpoints.map(&.url)
    {"/actuator", "/actuator/health", "/v3/api-docs", "/swagger-ui.html"}.each do |url|
      urls.should_not contain(url)
    end
  end
end
