require "../../func_spec.cr"

# Lexer-state and handler-scoping failures that each dropped later routes
# or params:
#
#   * a template nested in a `${ … }` substitution ended the outer literal
#     at the first inner backtick (`<li>`, `it's`), lexing the rest of the
#     file out of phase;
#   * `i++ / 2` and a JSX `</div>` opened a regex literal that ran on
#     past the end of the line;
#   * a regex inside a substitution (`${v.replace(/'/g, '')}`) opened a
#     string in the template scanner;
#   * an arrow inside the handler body (`items.map(i => …)`) was taken as
#     the handler, so the `req.query` reads above it were never scanned.
expected_endpoints = [
  Endpoint.new("/list", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/greet", "GET", [Param.new("name", "", "query")]),
  Endpoint.new("/count", "GET", [Param.new("n", "", "query")]),
  Endpoint.new("/after", "GET", [Param.new("token", "", "query")]),
  Endpoint.new("/page", "GET", [Param.new("name", "", "query")]),
  Endpoint.new("/submit", "POST", [Param.new("t", "", "json")]),
  Endpoint.new("/users/:id", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/javascript/express_literal_nesting/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
