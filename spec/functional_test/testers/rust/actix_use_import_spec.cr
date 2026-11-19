require "../../func_spec.cr"

# Handlers and configure fns brought in with `use` (`use users::{user_config,
# list_all}`, `use crate::posts::configure as posts_config`) keep the scope
# they are mounted under, as does a handler imported into a configured fn of
# another file (`api::config` registers `crate::handlers::health`).
expected_endpoints = [
  Endpoint.new("/users/list", "GET"),
  Endpoint.new("/users/stats", "GET"),
  Endpoint.new("/posts/recent", "GET"),
  Endpoint.new("/all/everything", "GET"),
  Endpoint.new("/api/health", "GET"),
]

FunctionalTester.new("fixtures/rust/actix_use_import/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_actix_web"),
}).perform_tests
