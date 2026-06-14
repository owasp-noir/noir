require "../../func_spec.cr"

# `@Controller(RouteKey.User)` where `RouteKey` is an enum defined in a
# different file (`./enum`) and imported. The controller prefix must
# resolve cross-file (`users`/`assets`), not collapse to "" — which would
# leave bare `/me`, `/:id`, `/statistics` and even merge `/:id` from two
# controllers into one.
expected_endpoints = [
  Endpoint.new("/users/me", "GET"),
  Endpoint.new("/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/assets/statistics", "GET"),
]

FunctionalTester.new("fixtures/typescript/nestjs_cross_file_enum/", {
  :techs     => 1,
  :endpoints => 3,
}, expected_endpoints).perform_tests
