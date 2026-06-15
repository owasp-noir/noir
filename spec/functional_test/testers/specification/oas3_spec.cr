require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/pets", "GET", [
    Param.new("query", "", "query"),
    Param.new("sort", "", "query"),
    Param.new("cookie", "", "cookie"),
  ]),
  Endpoint.new("/pets", "POST", [
    Param.new("name", "", "json"),
  ]),
  Endpoint.new("/pets/{petId}", "GET", [Param.new("petId", "", "path")]),
  Endpoint.new("/pets/{petId}", "PUT", [
    Param.new("petId", "", "path"),
    Param.new("breed", "", "json"),
    Param.new("name", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/oas3/common/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

FunctionalTester.new("fixtures/specification/oas3/no_servers/", {
  :techs     => 1,
  :endpoints => 1,
}, nil).perform_tests

FunctionalTester.new("fixtures/specification/oas3/no_servers/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("https://api.example.com/gems", "GET"),
], {
  "url" => YAML::Any.new("https://api.example.com"),
}).perform_tests

FunctionalTester.new("fixtures/specification/oas3/multiple_docs/", {
  :techs     => 1,
  :endpoints => 2,
}, nil).perform_tests

FunctionalTester.new("fixtures/specification/oas3/nil_cast/", {
  :techs     => 1,
  :endpoints => 0,
}, nil).perform_tests

FunctionalTester.new("fixtures/specification/oas3/refs_multipart/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/users/{userId}/avatar", "POST", [
    Param.new("userId", "", "path"),
    Param.new("X-Trace-Id", "", "header"),
    Param.new("avatar", "", "form"),
    Param.new("caption", "", "form"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("email", "", "json"),
    Param.new("name", "", "json"),
    Param.new("password", "", "json"),
  ]),
]).perform_tests

FunctionalTester.new("fixtures/specification/oas3/param_in_path/", {
  :techs     => 1,
  :endpoints => 4,
}, [
  Endpoint.new("/gems_yml", "GET", [
    Param.new("query", "", "query"),
    Param.new("sort", "", "query"),
    Param.new("cookie", "", "cookie"),
  ]),
  Endpoint.new("/gems_yml", "PUT", [
    Param.new("query", "", "query"),
    Param.new("sort", "", "query"),
    Param.new("cookie", "", "cookie"),
  ]),
  Endpoint.new("/gems_json", "GET", [
    Param.new("query", "", "query"),
    Param.new("sort", "", "query"),
    Param.new("cookie", "", "cookie"),
  ]),
  Endpoint.new("/gems_json", "POST", [
    Param.new("query", "", "query"),
    Param.new("sort", "", "query"),
    Param.new("cookie", "", "cookie"),
  ]),
]).perform_tests

FunctionalTester.new("fixtures/specification/oas3/security_schemes/", {
  :techs     => 1,
  :endpoints => 4,
}, [
  Endpoint.new("/items", "GET", [
    Param.new("X-API-Key", "", "header"),
  ]),
  Endpoint.new("/items", "POST", [
    Param.new("name", "", "json"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/public", "GET"),
  Endpoint.new("/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("api_key", "", "query"),
    Param.new("SESSIONID", "", "cookie"),
  ]),
]).perform_tests

FunctionalTester.new("fixtures/specification/oas3/tab_in_block_scalar/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/widgets", "GET", [
    Param.new("state", "", "query"),
  ]),
  Endpoint.new("/widgets", "POST", [
    Param.new("name", "", "json"),
    Param.new("color", "", "json"),
  ]),
]).perform_tests

edge_case_endpoints = [
  Endpoint.new("/api/v2/orders", "GET", [
    Param.new("X-Tenant", "", "header"),
    Param.new("state", "", "query"),
  ]),
  Endpoint.new("/api/v2/orders", "POST", [
    Param.new("X-Tenant", "", "header"),
    Param.new("name", "", "json"),
    Param.new("priority", "", "json"),
    Param.new("notes", "", "json"),
  ]),
  Endpoint.new("/api/v2/reports", "POST", [
    Param.new("filter", "", "json"),
    Param.new("include_archived", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/oas3_edge_cases/", {
  :techs     => 1,
  :endpoints => edge_case_endpoints.size,
}, edge_case_endpoints).perform_tests

edge_case_url_endpoints = edge_case_endpoints.map do |endpoint|
  Endpoint.new("https://api.example.com#{endpoint.url}", endpoint.method, endpoint.params)
end

FunctionalTester.new("fixtures/specification/oas3_edge_cases/", {
  :techs     => 1,
  :endpoints => edge_case_url_endpoints.size,
}, edge_case_url_endpoints, {
  "url" => YAML::Any.new("https://api.example.com"),
}).perform_tests
