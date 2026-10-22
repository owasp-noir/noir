require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/generator", "GET", [] of Param),
  Endpoint.new("/generator", "POST", [
    Param.new("length", "", "form"),
  ]),
  Endpoint.new("/generator/<value>", "PUT", [
    Param.new("value", "", "path"),
  ]),
  Endpoint.new("/generator", "DELETE", [] of Param),
  Endpoint.new("/item/<item_id>", "GET", [
    Param.new("item_id", "", "path"),
    Param.new("X-Api-Token", "", "header"),
  ]),
  Endpoint.new("/item/<item_id>", "POST", [
    Param.new("item_id", "", "path"),
    Param.new("name", "", "form"),
  ]),
  Endpoint.new("/", "GET", [] of Param),
]

FunctionalTester.new("fixtures/python/cherrypy_method_dispatcher/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
