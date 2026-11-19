require "../../func_spec.cr"

# Route classes (typescript-express-starter): `public path = '/users'` and
# `this.router.get(`${this.path}`, …)` / `this.path + '/:id'`. The field
# was never read, so these routes were dropped or became `/{path}/:id`.
# A field two classes of one file set differently stays a placeholder.
FunctionalTester.new("fixtures/javascript/express_class_route_path/", {
  :techs     => 1,
  :endpoints => 5,
}, [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/{path}/status", "GET", [Param.new("path", "", "path")]),
]).perform_tests
