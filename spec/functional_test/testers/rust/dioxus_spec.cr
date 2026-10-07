require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/get_dogs", "POST", [
    Param.new("breed", "", "json"),
  ]),
  Endpoint.new("/api/custom/my_anonymous", "POST"),
  Endpoint.new("/api/users/{id}", "GET", [
    Param.new("page", "", "query"),
    Param.new("limit", "", "query"),
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/{user_id}/chat", "POST", [
    Param.new("room_id", "", "query"),
    Param.new("message", "", "json"),
    Param.new("user_id", "", "path"),
  ]),
  Endpoint.new("/api/items/:id", "PUT", [
    Param.new("item", "", "json"),
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/items/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/profile", "PATCH", [
    Param.new("nickname", "", "json"),
  ]),
  Endpoint.new("/api/search", "GET"),
]

FunctionalTester.new("fixtures/rust/dioxus/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
