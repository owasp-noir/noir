require "../../func_spec.cr"

# Comprehensive test for various JavaScript/Express code patterns
# These patterns test edge cases and modern JavaScript features
expected_endpoints = [
  # Case-insensitive HTTP methods (.Get, .Post, .Put, .Delete, .Patch)
  Endpoint.new("/case-get", "GET", [
    Param.new("param1", "", "query"),
  ]),
  Endpoint.new("/case-post", "POST", [
    Param.new("data", "", "json"),
  ]),
  Endpoint.new("/case-put", "PUT", [
    Param.new("value", "", "json"),
  ]),
  Endpoint.new("/case-delete", "DELETE"),
  Endpoint.new("/case-patch", "PATCH", [
    Param.new("field", "", "json"),
  ]),

  # Async/await patterns
  Endpoint.new("/async-simple", "GET", [
    Param.new("asyncParam", "", "query"),
  ]),
  Endpoint.new("/async-complex", "POST", [
    Param.new("title", "", "json"),
    Param.new("content", "", "json"),
    Param.new("User-Id", "", "header"),
    Param.new("authToken", "", "cookie"),
  ]),

  # Method chaining - all methods should be detected
  Endpoint.new("/chained-all", "GET", [
    Param.new("getParam", "", "query"),
  ]),
  Endpoint.new("/chained-all", "POST", [
    Param.new("postData", "", "json"),
  ]),
  Endpoint.new("/chained-all", "PUT", [
    Param.new("putData", "", "json"),
  ]),
  Endpoint.new("/chained-all", "DELETE"),

  # Named arrow function handler
  Endpoint.new("/named-arrow", "GET", [
    Param.new("arrowParam", "", "query"),
  ]),

  # Traditional function handler
  Endpoint.new("/traditional-function", "GET", [
    Param.new("tradParam", "", "query"),
  ]),

  # Multiline with middleware
  Endpoint.new("/multiline-middleware", "POST", [
    Param.new("username", "", "json"),
    Param.new("password", "", "json"),
    Param.new("Authorization", "", "header"),
  ]),

  # req.get() method for headers
  Endpoint.new("/header-get-method", "GET", [
    Param.new("X-Custom-Header", "", "header"),
    Param.new("X-Another-Header", "", "header"),
  ]),

  # Bracket notation for query params
  Endpoint.new("/bracket-query", "GET", [
    Param.new("param1", "", "query"),
    Param.new("param2", "", "query"),
  ]),

  # Bracket notation for cookies
  Endpoint.new("/bracket-cookie", "GET", [
    Param.new("sessionId", "", "cookie"),
    Param.new("trackingId", "", "cookie"),
  ]),

  # Mixed parameter patterns
  Endpoint.new("/mixed-params", "POST", [
    Param.new("field1", "", "json"),
    Param.new("field2", "", "json"),
    Param.new("field3", "", "json"),
    Param.new("field4", "", "json"),
    Param.new("qparam1", "", "query"),
    Param.new("qparam2", "", "query"),
    Param.new("qparam3", "", "query"),
    Param.new("x-header-1", "", "header"),
    Param.new("X-Header-2", "", "header"),
    Param.new("X-Header-3", "", "header"),
  ]),

  # App-level routes (not router-based)
  Endpoint.new("/app-level", "GET", [
    Param.new("appParam", "", "query"),
  ]),
  Endpoint.new("/app-level-post", "POST", [
    Param.new("appData", "", "json"),
  ]),

  # Single-line arrow function
  Endpoint.new("/single-arrow", "GET"),

  # Shorthand destructuring
  Endpoint.new("/shorthand-destructure", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
    Param.new("age", "", "json"),
  ]),

  # Default values in destructuring
  Endpoint.new("/default-destructure", "POST", [
    Param.new("theme", "", "json"),
    Param.new("language", "", "json"),
  ]),

  # Nested destructuring  
  # Note: Current implementation may not fully support nested destructuring
  # This is a known limitation
  Endpoint.new("/nested-destructure", "POST"),
]

FunctionalTester.new("fixtures/javascript/express_patterns/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
