require "../../func_spec.cr"

# Laravel heredoc/string structural test.
#
# Exercises the shared `Noir::PhpLexer` through the Laravel analyzer:
#   * Route-shaped calls living inside a `<<<HTML … HTML` heredoc, a
#     `<<<SQL … SQL` heredoc and a plain `"…"` string MUST NOT surface as
#     endpoints (false-positive suppression).
#   * A heredoc body inside a `Route::group(...)` closure contains stray
#     `{ } ;`. The lexer masks it, so the group brace still matches its true
#     close and the real `/admin/widgets` route keeps its `admin` prefix
#     instead of being dropped or mis-prefixed (false-negative recovery).
#   * Scanning resumes cleanly after the heredoc, so the trailing
#     `/notify` route is still found.
expected_endpoints = [
  Endpoint.new("/admin/widgets", "GET"),
  Endpoint.new("/notify", "POST"),
]

FunctionalTester.new("fixtures/php/laravel_heredoc/", {
  :techs     => 2,
  :endpoints => 2,
}, expected_endpoints).perform_tests
