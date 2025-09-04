require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/sign", "GET"),
  Endpoint.new("/sign", "POST", [Param.new("username", "", "form"), Param.new("password", "", "form")]),
  Endpoint.new("/cookie", "GET"),
  Endpoint.new("/login", "POST", [Param.new("username", "", "form"), Param.new("password", "", "form")]),
  Endpoint.new("/create_record", "PUT"),
  Endpoint.new("/delete_record", "DELETE", [Param.new("name", "", "json")]),
  Endpoint.new("/get_ip", "GET", [Param.new("X-Forwarded-For", "", "header")]),
  Endpoint.new("/", "GET"),
]

FunctionalTester.new("fixtures/python/flask/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests
