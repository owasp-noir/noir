require "../../func_spec.cr"

# A `routes![..]` entry is resolved to the file that defines the handler:
# `use`-imported handlers, an inline `mod`, rocket_okapi's
# `openapi_get_routes!` and a `let`-bound route list all keep their mount
# prefix. An unmounted handler keeps its bare path.
expected_endpoints = [
  Endpoint.new("/posts/recent", "GET"),
  Endpoint.new("/posts", "POST"),
  Endpoint.new("/hello/hello", "GET"),
  Endpoint.new("/hello/world", "GET"),
  Endpoint.new("/api/v1/users", "GET"),
  Endpoint.new("/v1/a", "GET"),
  Endpoint.new("/loose", "GET"),
]

FunctionalTester.new("fixtures/rust/rocket_mount_imports/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_rocket"),
}).perform_tests
