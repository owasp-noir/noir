require "../../func_spec.cr"

# #3318: `r.get true` serves the bare prefix, and `[Integer, true]` serves the
# route both with and without the integer segment.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/profile", "GET"),
  Endpoint.new("/settings/email", "GET"),
  Endpoint.new("/settings/password", "GET"),
  Endpoint.new("/settings/tokens", "GET"),
  Endpoint.new("/reports/income", "GET"),
  Endpoint.new("/reports/income/{year}", "GET", [Param.new("year", "", "path")]),
  # The block's params reach both rows of the optional matcher.
  Endpoint.new("/reports/entry", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/reports/entry/{id}", "GET", [Param.new("id", "", "path"), Param.new("q", "", "query")]),
]

FunctionalTester.new("fixtures/ruby/roda_tree/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
