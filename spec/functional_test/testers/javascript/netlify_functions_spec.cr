require "../../func_spec.cr"

# `config.path` (string or array) replaces the default
# `/.netlify/functions/<name>` URL and `config.method` narrows the verbs.
# Helpers, scheduled functions and edge functions without an inline path
# produce no endpoints.
FunctionalTester.new("fixtures/javascript/netlify_functions/", {
  :techs     => 1,
  :endpoints => 9,
}, [
  Endpoint.new("/api/hello", "GET", [Param.new("name", "", "query")]),
  Endpoint.new("/api/users/:id", "GET", [
    Param.new("id", "", "path"),
    Param.new("authorization", "", "header"),
  ]),
  Endpoint.new("/api/users/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("authorization", "", "header"),
  ]),
  Endpoint.new("/api/members/:id", "GET", [
    Param.new("id", "", "path"),
    Param.new("authorization", "", "header"),
  ]),
  Endpoint.new("/api/members/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("authorization", "", "header"),
  ]),
  # Lambda-compatible `exports.handler`, narrowed by its `httpMethod` check.
  Endpoint.new("/.netlify/functions/legacy", "POST", [
    Param.new("page", "", "query"),
    Param.new("title", "", "json"),
  ]),
  Endpoint.new("/.netlify/functions/status", "ANY"),
  Endpoint.new("/api/fetchable", "ANY", [Param.new("x-token", "", "header")]),
  Endpoint.new("/geo", "ANY", [Param.new("accept-language", "", "header")]),
]).perform_tests

# Functions directory moved by `[functions] directory` in netlify.toml.
FunctionalTester.new("fixtures/javascript/netlify_functions_config/", {
  :techs     => 2,
  :endpoints => 1,
}, [
  Endpoint.new("/.netlify/functions/ping", "ANY", [Param.new("message", "", "json")]),
]).perform_tests
