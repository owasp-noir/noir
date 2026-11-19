require "../../func_spec.cr"

# Endpoints configured with class attributes instead of `Configure()`, the
# fluent-generic `Ep.Req<T>.Res<U>` / `Ep.NoReq.Res<U>` bases, and a route
# held in a constant.
address_params = [Param.new("Id", "", "json"), Param.new("Street", "", "json")]

expected_endpoints = [
  Endpoint.new("/f01/address", "POST", address_params),
  Endpoint.new("/f02/address/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/f03/address", "POST", address_params),
  Endpoint.new("/f04/addresses", "GET"),
  Endpoint.new("/f05/address/{Id}", "DELETE", [Param.new("Id", "", "path"), Param.new("Street", "", "query")]),
  Endpoint.new("/f06/address/search", "GET"),
  Endpoint.new("/f07/address/ping", "GET"),
]

FunctionalTester.new("fixtures/csharp/fastendpoints_attributes/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
