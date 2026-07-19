require "../../func_spec.cr"

# Taffy declares the path as a component attribute and takes the HTTP
# verb from the handler function's name, so every route is statically
# known. `{token}` placeholders become path params; the remaining
# arguments are query params on GET and body params otherwise.
expected_endpoints = [
  # Tag syntax: taffy_uri + <cfargument>. `buildRepresentation` is not a
  # verb name, so it is not a handler.
  Endpoint.new("/artists", "GET"),
  Endpoint.new("/artists", "POST", [
    Param.new("firstname", "", "form"),
    Param.new("lastname", "", "form"),
  ]),

  # A token that is also declared as an argument stays a path param and
  # must not surface a second time as query/body.
  Endpoint.new("/artist/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/artist/{id}", "PUT", [
    Param.new("email", "", "form"),
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/artist/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),

  # Script syntax with the colon spelling. The braces in the URI must not
  # truncate the component header, and inline per-argument validators
  # (`taffy_minlength=`) must not be read as argument names.
  Endpoint.new("/echo/{parentId}/child/{childId}", "GET", [
    Param.new("parentId", "", "path"),
    Param.new("childId", "", "path"),
  ]),
  Endpoint.new("/echo/{parentId}/child/{childId}", "POST", [
    Param.new("name", "", "form"),
    Param.new("value", "", "form"),
  ]),

  # taffy_verb overrides the function name; a function with neither a
  # verb name nor the attribute is not a handler.
  Endpoint.new("/custom", "GET"),
  Endpoint.new("/custom", "PATCH"),
  Endpoint.new("/custom", "OPTIONS"),

  # One resource may answer on several comma-separated URIs.
  Endpoint.new("/alpha", "GET", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/beta", "GET", [
    Param.new("q", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/cfml/taffy/", {
  :techs     => 2, # Detection still sees cfml_taffy and cfml_pure
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
