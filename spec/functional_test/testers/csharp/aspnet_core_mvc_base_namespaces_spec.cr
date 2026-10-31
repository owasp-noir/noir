require "../../func_spec.cr"

# Two projects declare `ApiController` with different `[Route]` prefixes: the
# deriving file's `using` picks one; with none in reach no prefix is guessed.
# A verb-less `[Route]` action accepts every method.
expected_endpoints = [
  Endpoint.new("/alpha/users", "GET"),
  Endpoint.new("/alpha/users/search", "ANY"),
  Endpoint.new("/orders", "GET"),
]

FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_base_namespaces/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
