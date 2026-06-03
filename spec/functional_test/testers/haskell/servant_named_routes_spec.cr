require "../../func_spec.cr"

# Record-based `NamedRoutes` API: routes declared as record fields
# (`field :: mode :- <route>`), reached through `type API = NamedRoutes Routes`,
# including a nested record (`NamedRoutes ItemRoutes`) under a captured segment.
expected_endpoints = [
  Endpoint.new("/version", "GET"),
  Endpoint.new("/items", "GET", [
    Param.new("page", "Int", "query"),
  ]),
  Endpoint.new("/items", "POST", [
    Param.new("body", "Item", "body"),
  ]),
  Endpoint.new("/items/:itemId/detail", "GET", [
    Param.new("itemId", "Int", "path"),
  ]),
]

FunctionalTester.new("fixtures/haskell/servant_named_routes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
