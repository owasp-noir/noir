require "../../func_spec.cr"

# Tide: several verbs chained on one `.at()` binding (PUT + GET on the
# same path), `serve_dir`/`serve_file` static mounts (GET), `.nest("/api",
# subapp)` prefix composition, and `#[cfg(test)]` gating.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/:file", "PUT", [Param.new("file", "", "path")]),
  Endpoint.new("/:file", "GET", [Param.new("file", "", "path")]),
  Endpoint.new("/assets/*", "GET"),
  Endpoint.new("/favicon.ico", "GET"),
  Endpoint.new("/api/hello", "GET"),
]

FunctionalTester.new("fixtures/rust/tide_extras/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_tide"),
}).perform_tests
