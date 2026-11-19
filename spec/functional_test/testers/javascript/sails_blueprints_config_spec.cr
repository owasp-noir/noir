require "../../func_spec.cr"

# config/blueprints.js turns actions, rest and shortcuts off, so only the
# config/routes.js routes are served: no action shadow routes and no REST
# routes for LegacyController or the User model.
FunctionalTester.new("fixtures/javascript/sails_blueprints_config/", {
  :techs     => 1,
  :endpoints => 3,
}, [
  Endpoint.new("/", "GET"),
  Endpoint.new("/api/v1/entrance/login", "PUT"),
  Endpoint.new("/api/v1/account/update-password", "POST"),
]).perform_tests
