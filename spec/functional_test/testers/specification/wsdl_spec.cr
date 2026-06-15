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

# RPC-style messages declare each argument as its own `part` typed with a
# built-in scalar; the part name is the parameter. Both these (and the
# second part of a multi-part message) used to be dropped.
rpc_endpoints = [
  Endpoint.new("/services/Calculator/Add", "POST", [
    Param.new("SOAPAction", "http://example.com/calc/Add", "header"),
    Param.new("a", "", "json"),
    Param.new("b", "", "json"),
  ]),
  Endpoint.new("/services/Calculator/Square", "POST", [
    Param.new("SOAPAction", "http://example.com/calc/Square", "header"),
    Param.new("value", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/wsdl_rpc/", {
  :techs     => 1,
  :endpoints => rpc_endpoints.size,
}, rpc_endpoints).perform_tests

# WSDL split across files: service.wsdl holds the binding/service and
# imports interface.wsdl for the portType/message/types. The operation
# resolves only when the import is followed.
import_endpoints = [
  Endpoint.new("/services/AccountService/GetBalance", "POST", [
    Param.new("SOAPAction", "http://example.com/account/GetBalance", "header"),
    Param.new("accountId", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/wsdl_import/", {
  :techs     => 1,
  :endpoints => import_endpoints.size,
}, import_endpoints).perform_tests
