require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/page", "GET"),
  Endpoint.new("/page", "POST"),
  Endpoint.new("/page", "PUT"),
  Endpoint.new("/page", "PATCH"),
  Endpoint.new("/page", "DELETE"),
  Endpoint.new("/socket", "GET"),
  Endpoint.new("/live", "GET"),
  Endpoint.new("/phoenix/live_reload/socket", "GET"),
]

FunctionalTester.new("fixtures/elixir_phoenix/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).test_all
