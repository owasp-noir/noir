require "../../func_spec.cr"

# Character literals (`\(`, `\"`, `\;`, `\\`, `\newline`, `\tab`, `\uXXXX`,
# `\oNNN`) sit above and inside the routes. Reading them as raw characters
# collapses the reader's depth accounting, which used to drop every route in
# the file — so the whole point of this fixture is that both routes, with
# their callees, still come out.
rows_get = Endpoint.new("/rows", "GET")
rows_get.push_callee(Callee.new("response/ok", line: 15))
rows_get.push_callee(Callee.new("render-row", line: 15))
rows_get.push_callee(Callee.new("row.service/list", line: 15))

rows_post = Endpoint.new("/rows", "POST")
rows_post.push_callee(Callee.new("response/created", line: 19))
rows_post.push_callee(Callee.new("row.service/create!", line: 19))

expected_endpoints = [
  rows_get,
  rows_post,
]

FunctionalTester.new("fixtures/clojure/compojure_char_literals/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
