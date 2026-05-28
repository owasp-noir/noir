require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/users", "GET", [
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("X-Token", "", "header"),
  ]),
  Endpoint.new("/users/{id}", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/api/v1/items", "GET"),
  Endpoint.new("/projects/{project_id}", "GET", [
    Param.new("project_id", "", "path"),
  ]),
  Endpoint.new("/teams/{team_id}", "GET", [
    Param.new("team_id", "", "path"),
  ]),
  Endpoint.new("/organizations/{org_id}/{project_id}", "GET", [
    Param.new("org_id", "", "path"),
    Param.new("project_id", "", "path"),
  ]),
  Endpoint.new("/dashboard", "GET"),
  Endpoint.new("/profile", "GET"),
]

FunctionalTester.new("fixtures/ruby/roda/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
