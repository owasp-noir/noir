require "../../func_spec.cr"

# A loop over a bracket array of symbol or string literals unrolls like a
# `%w[...]` one; an array holding a runtime value stays as written.
expected_endpoints = [
  Endpoint.new("/legal/terms", "GET"),
  Endpoint.new("/legal/privacy", "GET"),
  Endpoint.new("/about", "GET"),
  Endpoint.new("/contact", "GET"),
  Endpoint.new("/auth/facebook/callback", "GET"),
  Endpoint.new("/auth/github/callback", "GET"),
  Endpoint.new("/p/{page}", "GET", [Param.new("page", "", "path")]),
  Endpoint.new("/after", "GET"),
]

FunctionalTester.new("fixtures/ruby/rails_array_loops/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
