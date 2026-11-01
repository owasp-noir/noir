require "../../func_spec.cr"

# Tests hostile syntax shapes (strings with braces/parens, interpolations with nested braces,
# triple-quoted strings, fake routes in comments) across all Scala analyzers.

# Akka HTTP
akka_expected = [
  Endpoint.new("/api/v1/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("detail", "", "query"),
  ]),
  Endpoint.new("/api/v1/users/{id}", "POST", [
    Param.new("id", "", "path"),
    Param.new("body", "String", "json"),
  ]),
  Endpoint.new("/api/v1/admin", "GET"),
]

FunctionalTester.new("fixtures/scala/hostile_akka/", {
  :techs     => 1,
  :endpoints => akka_expected.size,
}, akka_expected).perform_tests

# http4s
http4s_expected = [
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users", "POST", [Param.new("body", "UserDto", "json")]),
  Endpoint.new("/items", "GET", [Param.new("page", "", "query")]),
]

FunctionalTester.new("fixtures/scala/hostile_http4s/", {
  :techs     => 1,
  :endpoints => http4s_expected.size,
}, http4s_expected).perform_tests

# Scalatra
scalatra_expected = [
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
    Param.new("detail", "", "query"),
    Param.new("X-Custom-Token", "", "header"),
  ]),
  Endpoint.new("/submit", "POST", [Param.new("body", "", "json")]),
]

FunctionalTester.new("fixtures/scala/hostile_scalatra/", {
  :techs     => 1,
  :endpoints => scalatra_expected.size,
}, scalatra_expected).perform_tests

# Play
play_expected = [
  Endpoint.new("/sird/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/sird/items", "POST"),
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
    Param.new("X-Auth-Token", "", "header"),
    Param.new("detail", "", "query"),
  ]),
  Endpoint.new("/items", "POST", [Param.new("body", "", "json")]),
]

FunctionalTester.new("fixtures/scala/hostile_play/", {
  :techs     => 1,
  :endpoints => play_expected.size,
}, play_expected).perform_tests

# ZIO HTTP
zio_expected = [
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("filter", "", "query"),
    Param.new("X-Token", "", "header"),
  ]),
  Endpoint.new("/items", "POST", [
    Param.new("body", "", "json"),
    Param.new("category", "", "query"),
  ]),
  Endpoint.new("/declarative/{code}", "GET", [
    Param.new("code", "", "path"),
    Param.new("q", "", "query"),
    Param.new("X-Trace", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/scala/hostile_zio_http/", {
  :techs     => 1,
  :endpoints => zio_expected.size,
}, zio_expected).perform_tests

# Finatra
finatra_expected = [
  Endpoint.new("/api/orders/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/orders", "POST"),
]

FunctionalTester.new("fixtures/scala/hostile_finatra/", {
  :techs     => 1,
  :endpoints => finatra_expected.size,
}, finatra_expected).perform_tests

# CLI
cli_expected = [
  Endpoint.new("cli://Tool/serve", "CLI", [
    Param.new("port", "", "flag"),
    Param.new("host", "", "flag"),
  ]),
  Endpoint.new("cli://Tool", "CLI", [
    Param.new("root-flag", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/scala/hostile_cli/", {
  :techs     => 1,
  :endpoints => cli_expected.size,
}, cli_expected).perform_tests
