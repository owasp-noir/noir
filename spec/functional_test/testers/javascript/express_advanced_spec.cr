require "../../func_spec.cr"

# Test cases for advanced Express patterns
# These test multi-line definitions and modern patterns that ARE currently detected
# TODO: Add support for case-insensitive methods (.Get, .Post, etc.) - currently not detected
# TODO: Add support for arrow function definitions - currently not detected
# TODO: Add support for router.use() with nested routers - currently not detected
expected_endpoints = [
  # Multi-line route definitions (WORKING)
  Endpoint.new("/multiline-simple", "GET"),

  # Method chaining on routes (WORKING - first method only)
  Endpoint.new("/chained", "GET", [
    Param.new("getParam", "", "query"),
  ]),

  # Nested path parameters (WORKING)
  Endpoint.new("/users/:userId/posts/:postId", "GET", [
    Param.new("userId", "", "path"),
    Param.new("postId", "", "path"),
    Param.new("includeComments", "", "query"),
  ]),

  # Optional parameters (WORKING)
  Endpoint.new("/posts/:id?", "GET", [
    Param.new("id", "", "path"),
    Param.new("id?", "", "path"),
    Param.new("filter", "", "query"),
  ]),

  # Regex routes (NOW WORKING)
  Endpoint.new("/^\\/regex-(\\d+)$/", "GET"),

  # Array of paths (NOW WORKING)
  Endpoint.new("/array-a", "GET"),
  Endpoint.new("/array-b", "GET"),

  # Different parameter extraction patterns (WORKING)
  Endpoint.new("/extract-variations", "POST", [
    Param.new("field1", "", "json"),
    Param.new("field2", "", "json"),
    Param.new("field3", "", "json"),
    Param.new("directField", "", "json"),
    Param.new("bracketField", "", "json"),
    Param.new("query1", "", "query"),
    Param.new("x-custom-header", "", "header"),
    Param.new("X-Another-Header", "", "header"),
    Param.new("sessionId", "", "cookie"),
  ]),

  # Template literal paths (WORKING)
  Endpoint.new("/api/v2/template", "GET"),

  # Concatenated paths (WORKING)
  Endpoint.new("/api/v2/concat", "POST"),

  # Multiple middleware (WORKING)
  Endpoint.new("/multiple-middleware", "PUT"),

  # Nested router with prefix (NOW WORKING)
  Endpoint.new("/user/profile", "GET", [
    Param.new("fields", "", "query"),
    Param.new("X-User-Id", "", "header"),
  ]),
  Endpoint.new("/user/settings", "POST", [
    Param.new("theme", "", "json"),
    Param.new("language", "", "json"),
    Param.new("notifications", "", "json"),
    Param.new("sessionToken", "", "cookie"),
  ]),

  # Cross-file router mount (NOW WORKING)
  Endpoint.new("/api/users", "GET", [
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/api/users", "POST", [
    Param.new("name", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/javascript/express_advanced/", {
  :techs => 1,
}, expected_endpoints).perform_tests
