require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "GET", [
    Param.new("page", "", "query"),
    Param.new("Search", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("user_name", "", "form"),
    Param.new("handler", "Delete", "query"),
    Param.new("id", "", "form"),
    Param.new("Search", "", "form"),
  ]),
  Endpoint.new("/Orders", "GET", [
    Param.new("handler", "Stats", "query"),
  ]),
  Endpoint.new("/Orders", "POST", [
    Param.new("handler", "Archive", "query"),
    Param.new("X-Token", "", "header"),
    Param.new("limit", "", "query"),
    Param.new("Note", "", "form"),
  ]),
  Endpoint.new("/Users/Edit/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/Users/Edit/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("Input", "", "form"),
  ]),
  Endpoint.new("/Admin/Reports/{year}", "GET", [
    Param.new("year", "", "path"),
  ]),
  Endpoint.new("/counter", "GET", [
    Param.new("step", "", "query"),
  ]),
  Endpoint.new("/counter/{Start}", "GET", [
    Param.new("Start", "", "path"),
    Param.new("step", "", "query"),
  ]),
  Endpoint.new("/contact", "GET", [
    Param.new("ref", "", "query"),
  ]),
  Endpoint.new("/contact", "POST", [
    Param.new("Model", "", "form"),
  ]),
  Endpoint.new("/weather", "GET", [
    Param.new("City", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/csharp/razor/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests
