require "../../func_spec.cr"

# Upper-case extensions (`INDEX.CSHTML`, `RazorApp.CSPROJ`) as checked out
# from a case-insensitive Windows filesystem. The page still routes without
# its extension and still pairs with its lower-case `Index.cshtml.cs` model.
expected_endpoints = [
  Endpoint.new("/Users", "GET", [
    Param.new("page", "", "query"),
    Param.new("Search", "", "query"),
  ]),
  Endpoint.new("/Users", "POST", [
    Param.new("user_name", "", "form"),
    Param.new("handler", "Delete", "query"),
    Param.new("id", "", "form"),
    Param.new("Search", "", "form"),
  ]),
  Endpoint.new("/Users/EDIT/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/Users/EDIT/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("Input", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/csharp/razor_uppercase/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
