require "../../func_spec.cr"

# Routes drawn only under `if Rails.env.test?`-style conditions do not exist
# in production; an `else` branch and conditions production can satisfy
# keep theirs, and the frames inside balance so `/after` keeps no prefix.
expected_endpoints = [
  Endpoint.new("/up", "GET"),
  Endpoint.new("/prod_branch", "GET"),
  Endpoint.new("/prod_only", "GET"),
  Endpoint.new("/demo", "GET"),
  Endpoint.new("/either", "GET"),
  Endpoint.new("/after", "GET"),
]

FunctionalTester.new("fixtures/ruby/rails_nonprod_routes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
