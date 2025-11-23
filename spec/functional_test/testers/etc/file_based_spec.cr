require "../../func_spec.cr"
require "json"    # Ensure json is at top if structs use it
require "process" # Ensure Process is available at top

# Helper structs for parsing, matching the structure in src/models/endpoint.cr
# Moved to top-level to avoid "can't declare class dynamically" error.
# Note: The Endpoint and Param structs used by expected_endpoints are from func_spec.cr via noir models,
# not these Test* structs. These Test* structs are for the separate GraphQL CLI test.
struct TestPathInfo
  include JSON::Serializable
  property path : String
  property line : Int32 | Nil
end

struct TestDetails
  include JSON::Serializable
  property code_paths : Array(TestPathInfo) = [] of TestPathInfo
end

struct TestParam
  include JSON::Serializable
  property name : String
  property value : String
  property param_type : String
end

struct TestEndpoint
  include JSON::Serializable
  property url : String
  property method : String
  property params : Array(TestParam) = [] of TestParam
  property details : TestDetails
end

# Corrected spelling from extected_endpoints to expected_endpoints
expected_endpoints = [
  Endpoint.new("https://www.hahwul.com/", "GET"),
  Endpoint.new("https://www.hahwul.com/about", "GET"),
  Endpoint.new("https://www.hahwul.com/cullinan", "GET"),
  Endpoint.new("https://www.hahwul.com/phoenix", "GET"),
  Endpoint.new("https://www.hahwul.com/tag/security/", "GET"),
  Endpoint.new("https://www.hahwul.com/tag/crystal/", "GET"),
  Endpoint.new("https://www.hahwul.com/tag/zap/", "GET"),
  Endpoint.new("https://www.hahwul.com/form_http", "POST", [Param.new("X-API-Key", "1234", "header"), Param.new("a", "1234", "form")]),
  Endpoint.new("https://www.hahwul.com/json_http", "POST", [Param.new("name", "test", "json"), Param.new("data", "abcd", "json")]),
  Endpoint.new("https://www.hahwul.com/query_http", "GET", [Param.new("q", "1234", "query"), Param.new("Authorization", "abcd", "header")]),
  Endpoint.new("https://www.hahwul.com/multiple_http1", "GET"),
  Endpoint.new("https://www.hahwul.com/multiple_http2", "GET"),
  Endpoint.new("https://www.hahwul.com/graphql", "POST", [
    Param.new("graphql_operation_query_GetUserData", "{\"query\":\"GetUserData\"}", "json"),
  ]),
]

tester = FunctionalTester.new("fixtures/etc/file_based/", {
  :techs => 0,
  # Adjusted count: original 12 + 1 new unique GraphQL endpoint (POST /graphql)
  :endpoints => expected_endpoints.size, # This will now be 13 if original was 12
}, expected_endpoints)

tester.app.options["url"] = YAML::Any.new("https://www.hahwul.com")
