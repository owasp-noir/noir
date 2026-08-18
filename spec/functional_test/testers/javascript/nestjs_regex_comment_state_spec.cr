require "../../func_spec.cr"

# `JSRouteExtractor.strip_js_comments` tracked `'`, `"` and backticks but had
# no regex-literal state, so the unpaired quote in `str.replace(/'/g, ...)`
# inverted the string state for the rest of the file. That cut both ways:
#
#   * real comments stopped being blanked, so the commented-out
#     `// @Get('legacy-removed')` was reported as a live endpoint, and
#   * real string bodies were scanned as code, so the `/*` in
#     `blockOpen = '/*'` opened a block comment that blanked every route
#     below it.
#
# Asserting the count pins the phantom route as much as the real ones.
expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/create", "POST"),
]

FunctionalTester.new("fixtures/javascript/nestjs_regex_comment_state/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
