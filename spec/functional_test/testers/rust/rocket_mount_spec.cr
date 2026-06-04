require "../../func_spec.cr"

# Cross-file `.mount()` prefix composition. main.rs mounts handlers that
# live in sibling modules; the analyzer must prefix each `#[get]` route
# with the base it is mounted under. Covers the three real-world shapes:
#   * direct `routes![users::list, users::get_one]`           -> /users/*
#   * array-concat prefix `[base, "/admin"].concat()`         -> /admin/*
#   * `mount("/api", api::all_routes())` where the collector
#     aggregates `routes![ping]` + an aliased recursive append
#     `r.append(&mut v1_routes())` (v1_routes => v1::routes)   -> /api/*
expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/admin/dashboard", "GET"),
  Endpoint.new("/api/ping", "GET"),
  Endpoint.new("/api/status", "GET"),
]

FunctionalTester.new("fixtures/rust/rocket_mount/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_rocket"),
}).perform_tests
