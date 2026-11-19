require "../../func_spec.cr"

# MVC 5 `[AcceptVerbs]` (enum flags and strings) and `[ActionName]`.
expected_endpoints = [
  Endpoint.new("/Account/Login", "GET", [Param.new("returnUrl", "", "query")]),
  Endpoint.new("/Account/Save", "POST", [Param.new("name", "", "form")]),
  Endpoint.new("/Account/Both", "GET", [Param.new("id", "", "query")]),
  Endpoint.new("/Account/Both", "POST", [Param.new("id", "", "form")]),
  Endpoint.new("/Account/Replace", "PUT", [Param.new("id", "", "form")]),
  Endpoint.new("/Account/Delete", "GET", [Param.new("id", "", "query")]),
  Endpoint.new("/Account/Delete", "POST", [Param.new("id", "", "form")]),
]

FunctionalTester.new("fixtures/csharp/aspnet_mvc_accept_verbs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
