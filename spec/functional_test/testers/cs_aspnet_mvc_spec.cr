require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/Open/Callback/{appId}", "GET"),
  Endpoint.new("/data/default", "GET"),
]

FunctionalTester.new("fixtures/aspnet_mvc/", {
  :techs     => 1,
  :endpoints => 2,
}, extected_endpoints).test_all
