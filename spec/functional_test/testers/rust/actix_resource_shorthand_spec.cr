require "../../func_spec.cr"

# `web::resource("/p").get(h).post(h2)` (actix-web 4.4 shorthands),
# `web::to(h)` (any method, like `web::route().to(h)`) and a multi-pattern
# `web::resource(["/v1/ping", "/v2/ping"])`.
expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST", [Param.new("name", "", "json")]),
  Endpoint.new("/api/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/users/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/v1/ping", "GET"),
  Endpoint.new("/v2/ping", "GET"),
  Endpoint.new("/control", "GET"),
] + %w[GET POST PUT DELETE PATCH HEAD OPTIONS].map { |verb| Endpoint.new("/hook", verb) }

FunctionalTester.new("fixtures/rust/actix_resource_shorthand/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_actix_web"),
}).perform_tests
