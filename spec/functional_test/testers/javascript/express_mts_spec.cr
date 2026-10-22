require "../../func_spec.cr"

# `.mts` / `.cts` TypeScript modules are valid sources that both the
# detector and the JavaScript engine must accept; they used to detect
# nothing and scan nothing.
expected_endpoints = [
  Endpoint.new("/hello", "GET", [Param.new("name", "", "query")]),
  Endpoint.new("/admin/login", "POST", [Param.new("user", "", "json")]),
]

FunctionalTester.new("fixtures/javascript/express_mts/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
