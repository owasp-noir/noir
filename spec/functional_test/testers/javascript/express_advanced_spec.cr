require "../../func_spec.cr"

# Test cases for advanced Express patterns
# These test case-insensitive methods, multi-line definitions, and modern patterns
expected_endpoints = [
  # Case-insensitive HTTP methods
  Endpoint.new("/mixed-get", "GET", [
    Param.new("mixedParam", "", "query"),
  ]),
  Endpoint.new("/mixed-post", "POST", [
    Param.new("data", "", "json"),
  ]),
  Endpoint.new("/mixed-put", "PUT", [
    Param.new("value", "", "json"),
  ]),
  Endpoint.new("/mixed-delete", "DELETE"),
  Endpoint.new("/mixed-patch", "PATCH", [
    Param.new("field", "", "json"),
  ]),
  
  # Multi-line route definitions
  Endpoint.new("/multiline-simple", "GET", [
    Param.new("ml_param", "", "query"),
  ]),
  Endpoint.new("/multiline-with-middleware", "POST", [
    Param.new("username", "", "json"),
    Param.new("password", "", "json"),
    Param.new("Authorization", "", "header"),
  ]),
  
  # Async/await patterns
  Endpoint.new("/async-get", "GET", [
    Param.new("asyncParam", "", "query"),
  ]),
  Endpoint.new("/async-post", "POST", [
    Param.new("title", "", "json"),
    Param.new("content", "", "json"),
    Param.new("User-Id", "", "header"),
  ]),
  
  # Arrow function
  Endpoint.new("/arrow-function", "GET", [
    Param.new("arrowParam", "", "query"),
  ]),
  
  # Method chaining
  Endpoint.new("/chained", "GET", [
    Param.new("getParam", "", "query"),
  ]),
  Endpoint.new("/chained", "POST", [
    Param.new("postData", "", "json"),
  ]),
  Endpoint.new("/chained", "PUT", [
    Param.new("putData", "", "json"),
  ]),
  
  # Nested path parameters
  Endpoint.new("/users/:userId/posts/:postId", "GET", [
    Param.new("userId", "", "path"),
    Param.new("postId", "", "path"),
    Param.new("includeComments", "", "query"),
  ]),
  
  # Optional parameters
  Endpoint.new("/posts/:id?", "GET", [
    Param.new("id", "", "path"),
    Param.new("id?", "", "path"),
    Param.new("filter", "", "query"),
  ]),
  
  # Different parameter extraction patterns
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
  
  # Template literal paths
  Endpoint.new("/api/v2/template", "GET", [
    Param.new("templateParam", "", "query"),
  ]),
  
  # Concatenated paths
  Endpoint.new("/api/v2/concat", "POST", [
    Param.new("concatData", "", "json"),
  ]),
  
  # Multiple middleware
  Endpoint.new("/multiple-middleware", "PUT", [
    Param.new("updateData", "", "json"),
    Param.new("Authorization", "", "header"),
  ]),
  
  # Nested router with prefix
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
]

FunctionalTester.new("fixtures/javascript/express_advanced/", {
  :techs => 1,
}, expected_endpoints).perform_tests
