require "../../func_spec.cr"

# Two failures that both come from lexing JavaScript, in one semicolon-free
# Express file:
#
#   * `(s) => /["']/.test(s)` and `if (!/['"]/.test(...))` — the lexer's
#     regex-context check accepted only `( [ { , : ; =` and a keyword list,
#     so the '/' after `=>` or `!` lexed as division. The quote inside the
#     regex then opened a string token that ran to end of file and the scan
#     reported zero endpoints for the whole file.
#
#   * `app.route('/profile').get(...)` written without semicolons — the
#     chained-verb walk stopped only at a `;`, so it ran on through the
#     following statements and reported POST /profile and DELETE /profile
#     alongside the real POST /orders and DELETE /carts.
#
# The endpoint count is asserted so the two phantom /profile verbs cannot
# come back unnoticed.
expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/items", "POST", [
    Param.new("name", "", "json"),
  ]),
  Endpoint.new("/profile", "GET"),
  Endpoint.new("/orders", "POST"),
  Endpoint.new("/carts", "DELETE"),
]

FunctionalTester.new("fixtures/javascript/express_regex_literal_state/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
