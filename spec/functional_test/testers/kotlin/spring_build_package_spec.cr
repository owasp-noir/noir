require "../../func_spec.cr"

# `com.acme.build` is a source package, so its controller is reported; the
# `build/` directory beside build.gradle.kts is build output and is pruned,
# and so is `api/build/` beside the build-file-less subproject's `src/`
# (a stale kapt Java stub there would add `POST /api/stale` and java_spring).
expected_endpoints = [
  Endpoint.new("/build/list", "GET"),
  Endpoint.new("/api/users", "GET"),
]

FunctionalTester.new("fixtures/kotlin/spring_build_package/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
