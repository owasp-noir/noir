require "../../func_spec.cr"

# `config/apps.rb` mounts `core` at `/` (a no-op prefix) and `admin` at
# `/admin` — every route declared inside `app/admin/**` (both the plain
# `class Admin < Padrino::Application` routes and the `Admin.controllers
# :users do ... end` named routes, `map:` included) must inherit the
# `/admin` prefix, while `app/core/**` stays unprefixed.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/admin/dashboard", "GET", [
    Param.new("range", "", "query"),
  ]),
  Endpoint.new("/admin/users", "GET", [
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/admin/users/:id/profile", "GET", [
    Param.new("id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/ruby/padrino_mount/", {
  :techs     => 1,
  :endpoints => 5,
}, expected_endpoints).perform_tests
