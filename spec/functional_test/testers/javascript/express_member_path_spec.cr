require "../../func_spec.cr"

# A path or mount prefix given as a member of an object constant or a
# string enum (`app.get(ROUTES.users, …)`, `app.use(API.v1, router)`):
# the route was dropped, and `${ROUTES.users}` from a constants module
# with no template literal became a `{users}` path param.
FunctionalTester.new("fixtures/javascript/express_member_path/", {
  :techs     => 1,
  :endpoints => 6,
}, [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/:id", "PUT", [Param.new("id", "", "path"), Param.new("name", "", "json")]),
  Endpoint.new("/users/export", "GET"),
  Endpoint.new("/invoices", "GET"),
  Endpoint.new("/api/v1/leaf", "GET"),
]).perform_tests
