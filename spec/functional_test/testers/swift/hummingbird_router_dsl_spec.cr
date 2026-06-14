require "../../func_spec.cr"

# Exercises the `HummingbirdRouter` declarative result-builder DSL:
#   * `RouterBuilder { }` root with a top-level verb + inline group
#   * a `RouterController` whose `var body: some RouterMiddleware<Context>`
#     declares routes, with `RouteGroup` prefix composition (incl. nesting)
#   * verbs with a `handler:` reference, a trailing closure, and no path
#     (bound to the group root)
# The fixture also contains look-alike PascalCase constructors inside handler
# bodies (`Token(...)`, `Post(...)`) and a `: RouterMiddleware` conformance
# that must NOT surface as endpoints.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/admin/stats", "GET"),
  Endpoint.new("/user", "PUT"),
  Endpoint.new("/user/signup", "POST"),
  Endpoint.new("/user/login", "GET"),
  Endpoint.new("/user/mfa/enable", "POST"),
]

FunctionalTester.new("fixtures/swift/hummingbird_router_dsl/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
