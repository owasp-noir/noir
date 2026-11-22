require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/echo", "POST"),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{user_id}/posts/{post_id}", "GET", [Param.new("post_id", "", "path"), Param.new("user_id", "", "path")]),
  Endpoint.new("/search", "GET", [Param.new("page", "", "query"), Param.new("q", "", "query")]),
  Endpoint.new("/api/users", "POST", [Param.new("id", "", "json")]),
  Endpoint.new("/login", "POST", [Param.new("password", "", "form"), Param.new("username", "", "form")]),
  Endpoint.new("/protected", "GET", [Param.new("Authorization", "", "header")]),
  Endpoint.new("/session", "GET", [Param.new("session_id", "", "cookie")]),
  Endpoint.new("/articles/{id}", "PUT", [Param.new("X-API-Token", "", "header"), Param.new("id", "", "json"), Param.new("id", "", "path")]),
  Endpoint.new("/api/posts", "GET"),
  Endpoint.new("/api/reports/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/root/api/nested", "GET"),
  Endpoint.new("/grouped/tuple-a", "GET"),
  Endpoint.new("/grouped/tuple-b", "POST"),
]

FunctionalTester.new("fixtures/rust/actix_web/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
