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
  Endpoint.new("/explicit-get", "GET"),
  Endpoint.new("/blog/:root_capture", "GET", [
    Param.new("root_capture", "", "path"),
  ]),
  Endpoint.new("/blog/:root_capture/comments", "GET", [
    Param.new("root_capture", "", "path"),
  ]),
  Endpoint.new("/blog/:root_capture/archive", "GET", [
    Param.new("root_capture", "", "path"),
  ]),
  Endpoint.new("/ops", "GET"),
  Endpoint.new("/ops/dashboard", "GET"),
  Endpoint.new("/ops/item/:arg", "POST", [
    Param.new("arg", "", "path"),
  ]),
  Endpoint.new("/preflight", "OPTIONS"),
  # Moose-role composition: Controller::Widget composes Role::Resource (which
  # itself composes Role::Chain for the setup/base/object skeleton) and sets
  # `setup`'s PathPart to `widgets` via config. The role-carried CRUD actions
  # resolve to their real paths once flattened into the controller.
  Endpoint.new("/widgets", "GET"),
  Endpoint.new("/widgets/:object_capture/delete", "GET", [
    Param.new("object_capture", "", "path"),
  ]),
  # NB: lib/MyApp/Role/Crud.pm carries a `purge : Chained('object')` action
  # that NO controller composes, so it must NOT surface as a phantom `/purge`
  # route — asserting unresolvable fragments are still dropped, not emitted.
]

FunctionalTester.new("fixtures/perl/catalyst/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
