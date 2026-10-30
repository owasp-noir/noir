require "../../func_spec.cr"

# Rocket's `<name..>` matches zero or more segments, so it is reported as the
# rest placeholder `{*name}` (which `trace` reads as a catch-all), not as a
# one-segment `{name}`. The param keeps its bare name.
expected_endpoints = [
  Endpoint.new("/{*p}", "GET", [
    Param.new("p", "", "path"),
  ]),
  Endpoint.new("/static/{*file}", "GET", [
    Param.new("file", "", "path"),
  ]),
  Endpoint.new("/users/{id}/files/{*rest}", "GET", [
    Param.new("id", "", "path"),
    Param.new("rest", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/rust/rocket_segments/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
