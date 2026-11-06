require "../../func_spec.cr"

# `const { users, nested: { deep } } = require(...)` and
# `const { admin, opts = {} } = require(...)`: a destructuring with one
# level of nested braces still names the routers it imports.
FunctionalTester.new("fixtures/javascript/express_nested_destructure_require/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/api/list", "GET"),
  Endpoint.new("/adm/stats", "GET"),
]).perform_tests
