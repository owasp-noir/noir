require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/api/v2/users/me", "GET"),
  Endpoint.new("/api/v2/users/me/password", "PATCH"),
  Endpoint.new("/api/v2/users", "GET"),
  Endpoint.new("/api/v2/users", "POST"),
  Endpoint.new("/api/v2/users/{id}", "DELETE"),
  Endpoint.new("/api/v2/users/{id}", "PATCH"),
  Endpoint.new("/api/v2/users/{id}/password", "PATCH"),
  Endpoint.new("/api/v2/users/me/authentication-activity", "GET"),
  Endpoint.new("/api/v2/users/authentication-activity", "GET"),
  Endpoint.new("/api/v2/users/{id}/authentication-activity/latest", "GET"),
]

FunctionalTester.new("fixtures/kotlin_spring/", {
  :techs     => 1,
  :endpoints => 10,
}, extected_endpoints).test_all
