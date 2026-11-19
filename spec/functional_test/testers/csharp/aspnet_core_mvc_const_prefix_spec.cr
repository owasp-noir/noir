require "../../func_spec.cr"

# `[Route(Constants.PrefixApi)]` on a base controller is read from the
# constant's declaration; one that cannot be read is kept as a placeholder
# (`/{Unknown}/other`, tagged `unresolved-route`), never dropped.
expected_endpoints = [
  Endpoint.new("/api/apps/{app}/clients", "ANY", [Param.new("app", "", "path")]),
  Endpoint.new("/api/apps/{app}/clients/{id}", "DELETE", [Param.new("app", "", "path"), Param.new("id", "", "path")]),
  Endpoint.new("/{Unknown}/other", "GET", [Param.new("Unknown", "", "path")]),
  Endpoint.new("/secure/guarded", "GET"),
  Endpoint.new("/secure/open", "GET"),
  Endpoint.new("/secure/header", "GET"),
  Endpoint.new("/secure/plain", "GET"),
  Endpoint.new("/whole/inside", "GET"),
  Endpoint.new("/whole/lifted", "GET"),
]

FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_const_prefix/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
