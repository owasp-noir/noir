require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/Open/Callback/{appId}", "GET", [
    Param.new("appId", "", "path"),
  ]),
  Endpoint.new("/data/default", "GET"),
  Endpoint.new("/User/Details", "GET", [
    Param.new("id", "", "query"),
  ]),
  Endpoint.new("/User/Search", "GET", [
    Param.new("query", "", "query"),
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/User/Create", "POST", [
    Param.new("name", "", "form"),
    Param.new("email", "", "form"),
  ]),
  Endpoint.new("/User/Update", "PUT", [
    Param.new("id", "", "form"),
    Param.new("name", "", "form"),
  ]),
  Endpoint.new("/User/Delete", "DELETE", [
    Param.new("id", "", "query"),
  ]),
  Endpoint.new("/Product/List", "GET", [
    Param.new("categoryId", "", "query"),
    Param.new("sortBy", "", "query"),
  ]),
  Endpoint.new("/Product/Add", "POST", [
    Param.new("productName", "", "form"),
    Param.new("price", "", "form"),
    Param.new("stock", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/csharp/aspnet_mvc/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests
