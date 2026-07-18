require "../../func_spec.cr"

# VS Code REST Client dialect: multiple requests, headers, a JSON body,
# a form body and `{{var}}` path/placeholder handling.
vscode_endpoints = [
  Endpoint.new("/users/:userId", "GET", [
    Param.new("Authorization", "Bearer {{token}}", "header"),
    Param.new("verbose", "", "query"),
    Param.new("userId", "", "path"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("name", "noir", "json"),
    Param.new("email", "noir@example.com", "json"),
  ]),
  Endpoint.new("/users/:userId", "PUT", [
    Param.new("name", "updated", "form"),
    Param.new("active", "true", "form"),
    Param.new("userId", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/specification/http_file/vscode/", {
  :techs     => 1,
  :endpoints => vscode_endpoints.size,
}, vscode_endpoints).perform_tests

# JetBrains HTTP Client dialect: an `@var` base URL and a `> {% ... %}`
# response-handler block that must not leak into endpoints.
jetbrains_endpoints = [
  Endpoint.new("/orders", "POST", [
    Param.new("item", "widget", "json"),
    Param.new("qty", "3", "json"),
  ]),
  Endpoint.new("/orders", "GET", [
    Param.new("status", "", "query"),
    Param.new("Accept", "application/json", "header"),
  ]),
]

FunctionalTester.new("fixtures/specification/http_file/jetbrains/", {
  :techs     => 1,
  :endpoints => jetbrains_endpoints.size,
}, jetbrains_endpoints).perform_tests

# `.rest` extension is parsed the same as `.http`.
FunctionalTester.new("fixtures/specification/http_file/rest_ext/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("/ping", "GET"),
]).perform_tests
