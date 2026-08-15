require "../../func_spec.cr"

expected_endpoints = [
  # Blueprint CRUD routes bound to UserController.js (no matching model
  # file needed -- Sails still binds the default REST actions).
  Endpoint.new("/user", "GET"),
  Endpoint.new("/user", "POST"),
  Endpoint.new("/user/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/user/:id", "PATCH", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/user/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),

  # Blueprint CRUD routes bound to api/models/Post.js -- no controller
  # file at all, the model alone is enough.
  Endpoint.new("/post", "GET"),
  Endpoint.new("/post", "POST"),
  Endpoint.new("/post/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/post/:id", "PATCH", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/post/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),

  # "actions2" standalone action file nested under api/controllers/user/,
  # addressed by its path relative to api/controllers -- /user/find-one.
  # A shadow route responds to every HTTP verb.
  Endpoint.new("/user/find-one", "GET"),
  Endpoint.new("/user/find-one", "POST"),
  Endpoint.new("/user/find-one", "PUT"),
  Endpoint.new("/user/find-one", "DELETE"),
  Endpoint.new("/user/find-one", "PATCH"),
  Endpoint.new("/user/find-one", "HEAD"),
  Endpoint.new("/user/find-one", "OPTIONS"),

  # Top-level standalone action file, not nested under a subdirectory.
  Endpoint.new("/login", "GET"),
  Endpoint.new("/login", "POST"),
  Endpoint.new("/login", "PUT"),
  Endpoint.new("/login", "DELETE"),
  Endpoint.new("/login", "PATCH"),
  Endpoint.new("/login", "HEAD"),
  Endpoint.new("/login", "OPTIONS"),

  # Default `assets/` static directory.
  Endpoint.new("/style.css", "GET"),
]

FunctionalTester.new("fixtures/javascript/sails_blueprints/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
