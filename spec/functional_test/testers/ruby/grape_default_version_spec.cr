require "../../func_spec.cr"

# `version 'v1'` without `using:` is path versioning (Grape's default);
# `using: :header` and `:using => :param` add no segment, and a
# `version = ...` local is not a declaration.
expected_endpoints = [
  Endpoint.new("/api/v1/statuses/public_timeline", "GET"),
  Endpoint.new("/header_versioned", "GET"),
  Endpoint.new("/param_versioned", "GET", [Param.new("version", "", "query")]),
]

FunctionalTester.new("fixtures/ruby/grape_default_version/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
