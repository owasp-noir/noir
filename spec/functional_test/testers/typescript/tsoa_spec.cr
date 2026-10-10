require "../../func_spec.cr"

expected_endpoints = [
  # `@Path() userId` / `@Query() name?` take the argument's own name.
  Endpoint.new("/users/{userId}", "GET", [
    Param.new("userId", "", "path"),
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("body", "", "body"),
  ]),
  # `{userId}` binds the undecorated argument by name.
  Endpoint.new("/users/{userId}", "PUT", [
    Param.new("userId", "", "path"),
    Param.new("x-request-id", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/typescript/tsoa/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

# `routes.basePath` in tsoa.json prefixes every route; `spec.basePath` only
# moves the OpenAPI document and is ignored.
basepath_endpoints = [
  Endpoint.new("/v1/items/{itemId}", "GET", [
    Param.new("itemId", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/typescript/tsoa_basepath/", {
  :techs     => 1,
  :endpoints => basepath_endpoints.size,
}, basepath_endpoints).perform_tests

# Two tsoa apps under one scan base: only `prefixed/` sets
# `routes.basePath`, so `plain/` keeps its routes unprefixed.
FunctionalTester.new("fixtures/typescript/tsoa_multi_app/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/v1/items/{itemId}", "GET", [Param.new("itemId", "", "path")]),
]).perform_tests

# The same split given as two `-b` bases, where `tsoa_basepath/` has no
# package.json to mark it as its own app: the base itself is the boundary.
FunctionalTester.new("fixtures/typescript/tsoa/", {
  :techs     => 1,
  :endpoints => 4,
}, [
  Endpoint.new("/users/{userId}", "GET", [Param.new("userId", "", "path")]),
  Endpoint.new("/v1/items/{itemId}", "GET", [Param.new("itemId", "", "path")]),
], {
  "base" => YAML::Any.new([
    YAML::Any.new("./spec/functional_test/fixtures/typescript/tsoa"),
    YAML::Any.new("./spec/functional_test/fixtures/typescript/tsoa_basepath"),
  ]),
}).perform_tests
