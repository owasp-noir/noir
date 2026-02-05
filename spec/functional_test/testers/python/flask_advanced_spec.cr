require "../../func_spec.cr"

expected_endpoints = [
  # App-level shortcut decorators
  Endpoint.new("/app-get", "GET"),
  Endpoint.new("/app-post", "POST"),

  # Blueprint shortcut decorators
  Endpoint.new("/api/bp-get", "GET"),
  Endpoint.new("/api/bp-post", "POST", [Param.new("data", "", "form")]),
  Endpoint.new("/api/bp-put", "PUT"),
  Endpoint.new("/api/bp-patch", "PATCH"),
  Endpoint.new("/api/bp-delete", "DELETE"),

  # MethodView - UserAPI
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users", "POST", [Param.new("username", "", "form"), Param.new("email", "", "json")]),
  Endpoint.new("/api/users/<int:user_id>", "GET", [Param.new("username", "", "query")]),
  Endpoint.new("/api/users/<int:user_id>", "PUT"),
  Endpoint.new("/api/users/<int:user_id>", "DELETE"),

  # MethodView - ItemAPI
  Endpoint.new("/api/items", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/items", "POST", [Param.new("name", "", "json")]),
]

FunctionalTester.new("fixtures/python/flask_advanced/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
