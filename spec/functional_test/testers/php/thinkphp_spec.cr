require "../../func_spec.cr"

expected_endpoints = [
  # Explicit routes from route/app.php
  Endpoint.new("/hello/{name}", "GET", [
    Param.new("name", "", "path"),
  ]),
  Endpoint.new("/save", "POST"),
  Endpoint.new("/update", "PUT"),
  Endpoint.new("/update", "PATCH"),

  # Resource routes generated for "blog"
  Endpoint.new("/blog", "GET"),
  Endpoint.new("/blog/create", "GET"),
  Endpoint.new("/blog", "POST"),
  Endpoint.new("/blog/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/blog/{id}/edit", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/blog/{id}", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/blog/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),

  # Group routes with "admin" prefix
  Endpoint.new("/admin/dashboard", "GET"),
  Endpoint.new("/admin/users", "POST"),

  # Implicit routes from app/controller/UserController.php
  Endpoint.new("/user/index", "GET", [
    Param.new("page", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/user", "GET", [
    Param.new("page", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/user/view", "GET", [
    Param.new("id", "", "query"),
    Param.new("get_id", "", "query"),
    Param.new("name", "", "form"),
  ]),
  Endpoint.new("/user/view", "POST", [
    Param.new("id", "", "query"),
    Param.new("get_id", "", "query"),
    Param.new("name", "", "form"),
  ]),
  Endpoint.new("/user/create", "GET", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
  ]),
  Endpoint.new("/user/create", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/php/thinkphp/", {
  :techs     => 2,
  :endpoints => 19,
}, expected_endpoints).perform_tests
