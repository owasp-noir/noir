require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/sign", "GET"),
  Endpoint.new("/sign", "POST", [Param.new("username", "", "form"), Param.new("password", "", "form")]),
  Endpoint.new("/cookie", "GET", [Param.new("test", "", "cookie")]),
  Endpoint.new("/login", "POST", [Param.new("username", "", "form"), Param.new("password", "", "form")]),
  Endpoint.new("/create_record", "PUT", [Param.new("name", "", "form")]),
  Endpoint.new("/delete_record", "DELETE", [Param.new("name", "", "json")]),
  Endpoint.new("/get_ip", "GET", [Param.new("X-Forwarded-For", "", "header")]),
  Endpoint.new("/", "GET"),
]

FunctionalTester.new("fixtures/python/sanic/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests
