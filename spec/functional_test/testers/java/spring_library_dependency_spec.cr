require "../../func_spec.cr"

# A library module's dependencies reach the application that depends on it:
# `app` has only `implementation project(':common')`, and `common` (bootJar
# disabled) brings actuator, so the actuator rows belong to `app`, once.
# `tools` has the library on its test classpath only.
expected_endpoints = [
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/actuator", "GET"),
  Endpoint.new("/actuator/health", "GET"),
  Endpoint.new("/tools/ping", "GET"),
]

tester = FunctionalTester.new("fixtures/java/spring_library_dependency/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Spring library module dependencies", tags: "functional" do
  it "do not reach a test classpath" do
    tester.endpoints.map(&.url).should_not contain("/tools/actuator")
  end
end
