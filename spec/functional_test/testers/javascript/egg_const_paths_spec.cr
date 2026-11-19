require "../../func_spec.cr"

# Paths built from a string constant: `${prefix}/users` and `prefix + '/users'`.
FunctionalTester.new("fixtures/javascript/egg_const_paths/", {
  :techs     => 1,
  :endpoints => 3,
}, [
  Endpoint.new("/control", "GET"),
  Endpoint.new("/api/v1/users", "GET"),
  Endpoint.new("/api/v1/users", "POST"),
]).perform_tests
