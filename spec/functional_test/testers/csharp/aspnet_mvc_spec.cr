require "../../func_spec.cr"

expected_endpoints = [
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
  # New ApiController endpoints with attribute-based routing
  Endpoint.new("/api/Api/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("authorization", "", "header"),
  ]),
  Endpoint.new("/api/Api/users", "POST", [
    Param.new("userData", "", "json"),
    Param.new("apiKey", "", "header"),
  ]),
  Endpoint.new("/api/Api/products/{productId}", "PUT", [
    Param.new("productId", "", "path"),
    Param.new("productData", "", "json"),
    Param.new("contentType", "", "header"),
  ]),
  Endpoint.new("/api/Api/items/{itemId}", "DELETE", [
    Param.new("itemId", "", "path"),
    Param.new("confirm", "", "query"),
    Param.new("authorization", "", "header"),
  ]),
  Endpoint.new("/api/Api/search", "GET", [
    Param.new("term", "", "query"),
    Param.new("page", "", "query"),
    Param.new("acceptLanguage", "", "header"),
  ]),
  Endpoint.new("/api/Api/upload", "POST", [
    Param.new("fileName", "", "form"),
    Param.new("description", "", "form"),
    Param.new("contentType", "", "header"),
  ]),
  Endpoint.new("/api/Api/profile", "GET", [
    Param.new("sessionId", "", "cookie"),
    Param.new("preferences", "", "cookie"),
  ]),
]

FunctionalTester.new("fixtures/csharp/aspnet_mvc/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
