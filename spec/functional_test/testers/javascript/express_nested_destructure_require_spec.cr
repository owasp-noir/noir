require "../../func_spec.cr"

# `const { users, nested: { deep } } = require(...)` and
# `const { admin, opts = {} } = require(...)`: a destructuring with one
# level of nested braces (or two: `cfg: { a: { b } }`) still names the
# routers it imports.
FunctionalTester.new("fixtures/javascript/express_nested_destructure_require/", {
  :techs     => 1,
  :endpoints => 3,
}, [
  Endpoint.new("/api/list", "GET"),
  Endpoint.new("/adm/stats", "GET"),
  Endpoint.new("/ops/health", "GET"),
]).perform_tests
