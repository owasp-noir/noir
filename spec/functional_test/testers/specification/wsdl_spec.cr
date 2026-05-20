require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/services/UserService/GetUser", "POST", [
    Param.new("SOAPAction", "http://example.com/userservice/GetUser", "header"),
    Param.new("Content-Type", "text/xml; charset=utf-8", "header"),
    Param.new("userId", "", "json"),
    Param.new("includeProfile", "", "json"),
  ]),
  Endpoint.new("/services/UserService/CreateUser", "POST", [
    Param.new("SOAPAction", "http://example.com/userservice/CreateUser", "header"),
    Param.new("Content-Type", "text/xml; charset=utf-8", "header"),
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
    Param.new("password", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/wsdl/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
