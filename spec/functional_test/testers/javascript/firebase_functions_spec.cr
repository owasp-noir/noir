require "../../func_spec.cr"

FunctionalTester.new("fixtures/javascript/firebase_functions/", {
  :techs     => 1,
  :endpoints => 4,
}, [
  Endpoint.new("/helloWorld", "ANY", [
    Param.new("name", "", "query"),
    Param.new("x-api-key", "", "header"),
  ]),
  Endpoint.new("/addMessage", "POST", [Param.new("data", "", "json")]),
  Endpoint.new("/createOrder", "ANY", [
    Param.new("item", "", "json"),
    Param.new("quantity", "", "json"),
  ]),
  Endpoint.new("/getProfile", "POST", [Param.new("data", "", "json")]),
]).perform_tests

# `onRequest(app)` serves an Express app under the function name, whether the
# app is defined in the same file or imported into it.
FunctionalTester.new("fixtures/javascript/firebase_functions_express/", {
  :techs     => 2,
  :endpoints => 4,
}, [
  Endpoint.new("/api", "ANY"),
  Endpoint.new("/api/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/admin", "ANY"),
  Endpoint.new("/admin/ban", "POST", [Param.new("uid", "", "json")]),
]).perform_tests
