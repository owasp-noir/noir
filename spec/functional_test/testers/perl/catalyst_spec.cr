require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET", [
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/about", "GET"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/users/list", "GET", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/users/profile/:arg", "GET", [
    Param.new("arg", "", "path"),
    Param.new("X-User", "", "header"),
  ]),
  Endpoint.new("/users/:user_capture/edit", "GET", [
    Param.new("user_capture", "", "path"),
    Param.new("display_name", "", "form"),
  ]),
  Endpoint.new("/users/:user_capture", "PUT", [
    Param.new("user_capture", "", "path"),
    Param.new("display_name", "", "form"),
  ]),
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/item/:arg", "GET", [
    Param.new("arg", "", "path"),
    Param.new("verbose", "", "query"),
  ]),
  Endpoint.new("/api/item/:arg", "POST", [
    Param.new("arg", "", "path"),
    Param.new("name", "", "form"),
    Param.new("metadata", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/perl/catalyst/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
