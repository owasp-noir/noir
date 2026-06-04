require "../../func_spec.cr"

# Cross-file scope composition: the `web::scope("/auth").service(
# mod::handler)` tree lives in `main.rs`, but the `#[get]/#[post]`
# handlers it mounts are defined in sibling modules (`users.rs`,
# `posts.rs`, `admin.rs`). The analyzer must prefix each handler with
# the scope it is registered under in the *other* file, resolving the
# right scope module-aware so the `list` leaf shared by `posts` and
# `admin` keeps `/auth/v1/posts` distinct from `/admin/list`.
expected_endpoints = [
  Endpoint.new("/auth/me", "GET"),
  Endpoint.new("/auth/v1/users", "GET"),
  Endpoint.new("/auth/v1/posts", "POST"),
  Endpoint.new("/auth/v1/posts", "GET"),
  Endpoint.new("/admin/dashboard", "GET"),
  Endpoint.new("/admin/list", "GET"),
]

FunctionalTester.new("fixtures/rust/actix_crossfile_scope/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_actix_web"),
}).perform_tests
