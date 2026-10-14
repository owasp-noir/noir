require "../../func_spec.cr"

# poem-openapi `#[oai]` methods: each `param::{Query, Header, Cookie}`
# argument is one named parameter — the binding, or its
# `#[oai(name = "...")]` rename — not a generic `query` placeholder.
expected_endpoints = [
  Endpoint.new("/api/pets", "GET", [
    Param.new("status", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/api/pets/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("X-API-Key", "", "header"),
    Param.new("body", "", "json"),
    Param.new("session", "", "cookie"),
  ]),
]

FunctionalTester.new("fixtures/rust/poem_openapi_params/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_poem"),
}).perform_tests
