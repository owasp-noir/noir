require "../../func_spec.cr"

# An unnamed catch-all (`routes/[...].ts`) is a wildcard like `[...slug]`,
# not a literal segment. A bare file answers every verb.
expected_endpoints = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"].map do |method|
  Endpoint.new("/*", method)
end

FunctionalTester.new("fixtures/javascript/nitro_catchall/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
