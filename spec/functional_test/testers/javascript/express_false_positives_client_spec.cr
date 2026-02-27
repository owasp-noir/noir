require "../../func_spec.cr"

# Regression tests for false positives caused by HTTP client calls in test files.
#
# Test files using frisby (or axios) make HTTP client calls that look syntactically
# similar to Express route definitions:
#
#   frisby.get(`${API_URL}/Recycles`)         ← client call, NOT a route
#   frisby.del(`${API_URL}/Recycles/1`, {})   ← client call, NOT a route
#   axios.post('http://localhost:3000/orders') ← client call, NOT a route
#
# These were previously extracted as routes because:
#   - `get`/`post`/`put`/`del` are HTTP-method tokens, matching the fast-scan pattern
#   - `parse_generic_route` (used when no framework token is found) lacked the
#     valid_route_path? filter, so http://... template literals slipped through
#
# The fixture has no server-side framework token ("express", "fastify", etc.),
# so noir detects 0 technologies and must produce 0 endpoints.

FunctionalTester.new("fixtures/javascript/express_false_positives_client/", {
  :techs     => 0,
  :endpoints => 0,
}, [] of Endpoint).perform_tests
