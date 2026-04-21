require "../../func_spec.cr"

# Regression test for --exclude-path.
#
# The fixture ships three Express files:
#   - app.js                 → real route, must survive
#   - app.test.js            → excluded by basename glob "*.test.js"
#   - tests/integration.js   → excluded by path glob "tests/*"
#
# With both patterns active only the /api/users route should appear.

expected_endpoints = [
  Endpoint.new("/api/users", "GET"),
]

overrides = Hash(String, YAML::Any).new
overrides["exclude_path"] = YAML::Any.new("*.test.js,tests/*")

FunctionalTester.new(
  "fixtures/javascript/express_exclude_path/",
  {
    :techs     => 1,
    :endpoints => expected_endpoints.size,
  },
  expected_endpoints,
  overrides,
).perform_tests
