require "../../func_spec.cr"

# `.api` request types expand into params: `form` from the query on a GET
# (the form body otherwise), `header`, and `json` from the body.
expected_endpoints = [
  Endpoint.new("/api/v1/users/:id", "GET", [Param.new("id", "", "path"), Param.new("fields", "", "query"), Param.new("X-Token", "", "header")]),
  Endpoint.new("/api/v1/users/:id", "PUT", [Param.new("id", "", "path"), Param.new("nickname", "", "json")]),
  Endpoint.new("/api/v1/search", "POST", [Param.new("q", "", "form"), Param.new("page", "", "form")]),
  Endpoint.new("/api/v1/ping", "GET"),
]

FunctionalTester.new("fixtures/go/gozero_api_types/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
