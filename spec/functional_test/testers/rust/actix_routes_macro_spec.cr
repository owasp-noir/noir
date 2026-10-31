require "../../func_spec.cr"

# A project-local `#[routes::routes(routes("p" => verb(handler), "p" => sub(Api)))]`
# table (Meilisearch): prefixes compose through `sub(...)` across files, two
# files declaring an `ItemsApi` are told apart by the `items::` / `other::`
# module in the ref, comments inside the table are ignored, and
# `AwebQueryParameter` reads its struct (deserr camelCase), and a `$( $route => ..)`
# repetition is filled from the `make_setting_routes!({route: ..})` records.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/items", "GET", [Param.new("pageSize", "", "query")]),
  Endpoint.new("/items", "POST", [Param.new("body", "", "json")]),
  Endpoint.new("/items/{item_id}", "GET", [Param.new("item_id", "", "path")]),
  Endpoint.new("/items/{item_id}", "DELETE", [Param.new("item_id", "", "path")]),
  Endpoint.new("/items/{item_id}/tags", "GET", [Param.new("item_id", "", "path")]),
  Endpoint.new("/other/ping", "GET"),
  Endpoint.new("/settings", "GET"),
  Endpoint.new("/settings/dictionary", "GET"),
  Endpoint.new("/settings/dictionary", "PUT"),
  Endpoint.new("/settings/pagination", "GET"),
  Endpoint.new("/settings/pagination", "PATCH"),
]

FunctionalTester.new("fixtures/rust/actix_routes_macro/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_actix_web"),
}).perform_tests
