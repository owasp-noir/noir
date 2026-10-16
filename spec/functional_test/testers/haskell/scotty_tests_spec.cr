require "../../func_spec.cr"

# `test/` and `spec/` trees, `FooSpec.hs` files and files importing
# `Test.Hspec.Wai` hold hspec-wai client requests and throwaway test apps,
# not routes the application serves. `src/Test/` is a production namespace.
expected_endpoints = [
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("body", "JSON", "body"),
  ]),
  Endpoint.new("/health", "GET"),
]

FunctionalTester.new("fixtures/haskell/scotty_tests/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
