require "../../func_spec.cr"

# `[Route(Constants.PrefixApi)]` on a base controller is read from the
# constant's declaration; one that cannot be read adds no prefix.
expected_endpoints = [
  Endpoint.new("/api/apps/{app}/clients", "GET", [Param.new("app", "", "path")]),
  Endpoint.new("/api/apps/{app}/clients/{id}", "DELETE", [Param.new("app", "", "path"), Param.new("id", "", "path")]),
  Endpoint.new("/other", "GET"),
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
