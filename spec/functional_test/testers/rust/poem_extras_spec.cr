require "../../func_spec.cr"

# poem: verb-less `.at(path, handler)` registers a GET endpoint;
# single-arg `req.header("X")` is a request header param; a two-arg
# response-builder `.header(name, value)` is NOT; `#[cfg(test)]` routes
# are excluded.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/whoami", "GET", [
    Param.new("X-Request-Id", "", "header"),
  ]),
  Endpoint.new("/redirect", "GET"),
]

FunctionalTester.new("fixtures/rust/poem_extras/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_poem"),
}).perform_tests
