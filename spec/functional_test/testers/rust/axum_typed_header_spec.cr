require "../../func_spec.cr"

# Axum `TypedHeader<T>` extractors name a header through the `headers`
# crate type: `Authorization<Bearer>` → `Authorization`, `UserAgent` →
# `User-Agent`, `ContentType` → `Content-Type`.
expected_endpoints = [
  Endpoint.new("/api/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/files/{*path}", "GET", [Param.new("path", "", "path")]),
  Endpoint.new("/api/me", "GET", [Param.new("Authorization", "", "header")]),
  Endpoint.new("/api/upload", "POST", [
    Param.new("User-Agent", "", "header"),
    Param.new("Content-Type", "", "header"),
  ]),
  Endpoint.new("/search", "GET", [Param.new("query", "", "query"), Param.new("user-agent", "", "header")]),
]

FunctionalTester.new("fixtures/rust/axum_typed_header/", {
  :techs => 1,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_axum"),
}).perform_tests
