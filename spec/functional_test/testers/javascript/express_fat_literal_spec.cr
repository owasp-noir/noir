require "../../func_spec.cr"

# A hand-written Express module that carries one fat inline literal (here
# a ~20 KB base64 data URI; an embedded JWKS, a long regex or a JSON seed
# behave the same). The whole-file average line length is dragged over
# `MINIFIED_AVG_LINE_THRESHOLD` by that single line, which used to make
# `minified_content?` call the file a bundle — every route below was then
# dropped silently, with no warning, no `errors` entry and exit 0.
expected_endpoints = [
  Endpoint.new("/logo", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/health", "GET"),
]

FunctionalTester.new("fixtures/javascript/express_fat_literal/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
