require "../../func_spec.cr"

# A slash-less pattern next to a `Handler` variable or a handler object is a
# route when it reads as one: it carries a slash or a `{param}`, sits in a
# `path()` / `routes()` group, or is `addHandler(HandlerType.X, ..)`. The
# collection calls that share the verb names (`sessions.put("k", new ..)`,
# `sessions.put("handlers", getOne)`, `row.get("C", String.class)`, and a
# `put` inside a `before(ctx -> ..)` handler body) must stay suppressed.
expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{id}", "GET"),
  Endpoint.new("/users/new", "POST"),
  Endpoint.new("/reports", "GET"),
  Endpoint.new("/users/{id}/profile", "GET"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/items/{id}", "GET"),
  Endpoint.new("/files/list", "GET"),
]

FunctionalTester.new("fixtures/java/lambda_dsl_handler_objects/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
