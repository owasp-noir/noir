require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET", [Param.new("x-api-key", "", "header")]),
  Endpoint.new("/paren", "GET", [Param.new("kind", "", "query")]),
  Endpoint.new("/socket", "GET"),
  # HTTP QUERY (RFC 10008, kemalcr/kemal#769) block form. `before_query` /
  # `after_query` filters below (same base path) must NOT appear as
  # endpoints — mirrors how `before_get`/`after_get` are already excluded.
  Endpoint.new("/search", "QUERY", [
    Param.new("q", "", "json"),
    Param.new("mode", "", "query"),
  ]),
  Endpoint.new("/query", "POST", [
    Param.new("query", "", "form"),
    Param.new("my_auth", "", "cookie"),
  ]),
  Endpoint.new("/token", "GET", [
    Param.new("grant_type", "", "form"),
    Param.new("redirect_url", "", "form"),
    Param.new("client_id", "", "form"),
  ]),
  Endpoint.new("/api/v1/users/", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/v1/users/:id", "GET"),
  # Real route declared after a `<<-MD … MD` doc heredoc — proves the
  # terminator stops the masking instead of blanking the rest of the file.
  # The example `get`/`post` calls inside the heredoc must NOT appear.
  Endpoint.new("/after-heredoc", "GET"),
  Endpoint.new("/1.html", "GET"),
  Endpoint.new("/2.html", "GET"),
]

FunctionalTester.new("fixtures/crystal/kemal/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
