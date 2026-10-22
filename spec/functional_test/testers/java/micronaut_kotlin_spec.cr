require "../../func_spec.cr"

# Micronaut controllers written in Kotlin (#2856): context path from
# `application.yml`, implicit URI variables, a `{?q,limit}` query
# template, `@Body` data classes resolved across files (also through a
# `Mono<T>` wrapper), a form `consumes`, `@CustomHttpMethod` and a
# `@ServerWebSocket`.
socket = Endpoint.new("/v1/ws/books/{topic}", "GET", [Param.new("topic", "", "path")])
socket.protocol = "ws"

book_fields = ->(format : String) {
  [Param.new("title", "", format), Param.new("author", "", format), Param.new("year", "", format)]
}

expected_endpoints = [
  Endpoint.new("/v1/books", "GET", [
    Param.new("max", "10", "query"),
    Param.new("X-Trace", "", "header"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("repository.findAll", line: 25))
  end,
  Endpoint.new("/v1/books/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/v1/books/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/v1/books", "POST", book_fields.call("json")),
  Endpoint.new("/v1/books/form", "POST", book_fields.call("form")),
  Endpoint.new("/v1/books/{id}", "PUT", [Param.new("id", "", "path")] + book_fields.call("json")),
  Endpoint.new("/v1/books/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/v1/books/advanced", "QUERY", book_fields.call("json")),
  socket,
]

FunctionalTester.new("fixtures/java/micronaut_kotlin/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
