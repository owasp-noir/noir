require "../../func_spec.cr"

# The preview TS config (`wasp-config`, Wasp 0.15–0.23).
expected_endpoints = [
  Endpoint.new("/dashboard", "GET"),
  Endpoint.new("/operations/get-reports", "POST", [
    Param.new("year", "", "json"),
    Param.new("quarter", "", "json"),
  ]),
  Endpoint.new("/reports/:reportId/csv", "GET", [
    Param.new("reportId", "", "path"),
    Param.new("columns", "", "query"),
  ]),
  Endpoint.new("/auth/me", "GET"),
  Endpoint.new("/auth/logout", "POST"),
  Endpoint.new("/auth/username/login", "POST", [Param.new("username", "", "json"), Param.new("password", "", "json")]),
  Endpoint.new("/auth/username/signup", "POST", [Param.new("username", "", "json"), Param.new("password", "", "json")]),
]

FunctionalTester.new("fixtures/typescript/wasp_config/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
