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
  property line : Int32?
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
  # prose.md — a URL literal carries the surrounding prose/markup with it
  # unless it is trimmed: `](url)` drops the closing paren, `<url>` and
  # `<link>url</link>` stop at the angle bracket, and a sentence-final `.`
  # is not part of the URL.
  Endpoint.new("https://www.hahwul.com/changelog/", "GET"),
  Endpoint.new("https://www.hahwul.com/feed.xml", "GET"),
  Endpoint.new("https://www.hahwul.com/sitemap", "GET"),
  # Both URLs on one line are reported, not only the first.
  Endpoint.new("https://www.hahwul.com/first", "GET"),
  Endpoint.new("https://www.hahwul.com/second", "GET"),
  # base64_mixed.txt — an undecodable base64-shaped token earlier in the
  # file must not abandon the rest of it.
  Endpoint.new("https://www.hahwul.com/hidden", "GET"),
]

tester = FunctionalTester.new("fixtures/etc/file_based/", {
  :techs     => 1, # http_file (the `.http` request files)
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.app.options["url"] = YAML::Any.new("https://www.hahwul.com")

# The url-matching FileAnalyzer hooks only run with `-u`, which is set on the
# runner above — so the assertions have to be kicked off after it, not by the
# constructor.
tester.perform_tests
