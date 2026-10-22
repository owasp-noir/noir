require "../../func_spec.cr"

expected_endpoints = [
  # No allowed_methods/2 and no cowboy_req:method/1 match, so the verb
  # stays unresolved.
  Endpoint.new("/", "ANY"),
  Endpoint.new("/health", "ANY"),
  # Verbs resolved from the handler's cowboy_req:method/1 branches.
  Endpoint.new("/users", "GET", [
    Param.new("page", "", "query"),
    Param.new("per_page", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("page", "", "query"),
    Param.new("per_page", "", "query"),
    Param.new("body", "Form", "body"),
  ]),
  # Verbs resolved from the REST handler's allowed_methods/2.
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
    Param.new("fields", "", "query"),
    Param.new("x-api-token", "", "header"),
  ]),
  Endpoint.new("/users/:id", "PUT", [
    Param.new("id", "", "path"),
    Param.new("fields", "", "query"),
    Param.new("x-api-token", "", "header"),
    Param.new("body", "", "body"),
  ]),
  Endpoint.new("/users/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("fields", "", "query"),
    Param.new("x-api-token", "", "header"),
  ]),
  # The 4-tuple {PathMatch, Constraints, Handler, State} form.
  Endpoint.new("/users/:id/avatar", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/:id/avatar", "POST", [
    Param.new("id", "", "path"),
  ]),
  # A binary path match rather than a string.
  Endpoint.new("/search", "GET"),
  # cowboy_static with the [...] wildcard segment.
  Endpoint.new("/static/*", "GET"),
]

FunctionalTester.new("fixtures/erlang/cowboy/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
