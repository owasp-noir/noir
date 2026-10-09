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

# `routes.basePath` in tsoa.json prefixes every route (`spec.basePath` is
# only the fallback).
basepath_endpoints = [
  Endpoint.new("/v1/items/{itemId}", "GET", [
    Param.new("itemId", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/typescript/tsoa_basepath/", {
  :techs     => 1,
  :endpoints => basepath_endpoints.size,
}, basepath_endpoints).perform_tests
