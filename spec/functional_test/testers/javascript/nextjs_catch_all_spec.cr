require "../../func_spec.cr"

# #3291: `[...x]` spans one or more segments (`{*x}`), and `[[...x]]` also
# serves the URL without it.
expected_endpoints = [
  Endpoint.new("/api/auth/{*nextauth}", "GET", [Param.new("nextauth", "", "path")]),
  Endpoint.new("/api/og/{*seed}", "GET", [Param.new("seed", "", "path")]),
  Endpoint.new("/api/og", "GET"),
]

FunctionalTester.new("fixtures/javascript/nextjs_catch_all/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
