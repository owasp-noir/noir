require "../../func_spec.cr"

# #3297.
# - A block-bodied lambda (and the springdoc `ops -> { ... }` third
#   argument) inside a `route()` chain no longer ends the router block.
# - `RouterFunctions.nest(path(...), route()...)` keeps its prefix, and
#   `.GET(path(...)[.and(...)], h)` reads the pattern off the predicate.
# - Java handlers report what they read off `ServerRequest`.
# - A `@RequestMapping` meta-annotation declared in another Maven module
#   (`common`) resolves for a controller in `app`.
expected_endpoints = [
  Endpoint.new("/users/{name}", "GET", [Param.new("name", "", "path")]),
  Endpoint.new("/users/search", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/users", "GET", [Param.new("keyword", "", "query")]),
  Endpoint.new("/users", "POST", [
    Param.new("X-Token", "", "header"),
    Param.new("username", "", "json"),
    Param.new("email", "", "json"),
  ]),
  Endpoint.new("/users/{name}", "DELETE", [Param.new("name", "", "path")]),
  Endpoint.new("/complete-profile", "GET"),
  Endpoint.new("/complete-profile/send-email-code", "POST"),
  Endpoint.new("/system/setup", "GET"),
  Endpoint.new("/system/status", "GET"),
  Endpoint.new("/system/setup", "POST"),
  Endpoint.new("/auth/login", "POST"),
  Endpoint.new("/auth/info", "GET"),
]

FunctionalTester.new("fixtures/java/spring_functional_router/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
