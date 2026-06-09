require "../../func_spec.cr"

# Cross-file `.configure()` prefix composition. main.rs mounts each module's
# `configure` fn under a scope (`web::scope("/auth").configure(...)`,
# `web::scope("/api").configure(api::configure)`); the analyzer prepends that
# scope prefix to the builder routes the fn registers in another file, on top
# of any internal scope (`/api` + `/v2` + `/graphql`).
expected_endpoints = [
  Endpoint.new("/auth/login", "POST"),
  Endpoint.new("/auth/logout", "GET"),
  Endpoint.new("/api/graphql", "POST"),
  Endpoint.new("/api/v2/graphql", "GET"),
  Endpoint.new("/other", "GET"),
  Endpoint.new("/v1/todos", "GET"),
  Endpoint.new("/v1/todos", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/v1/user/login", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/v1/user/info", "GET"),
]

FunctionalTester.new("fixtures/rust/actix_configure/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_actix_web"),
}).perform_tests
