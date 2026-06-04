require "../../func_spec.cr"

# Builder-style actix-web routing with a glob import (`use
# actix_web::web::*`). Exercises: bare verb identifiers (`get()`,
# `post()`), bare `scope(...)` / `resource(...)`, nested scope prefix
# composition through `.service(scope(...))`, the empty-path
# `.route("", ...)` scope-root form, the generic multi-method
# `#[route("/p", method = "GET", method = "POST")]` macro, regex path
# param normalisation (`{id:\d+}` -> `{id}`), and `#[cfg(test)]` gating.
expected_endpoints = [
  Endpoint.new("/api/v4/site", "GET"),
  Endpoint.new("/api/v4/site", "POST"),
  Endpoint.new("/api/v4/search", "GET"),
  Endpoint.new("/api/v4/community", "GET"),
  Endpoint.new("/api/v4/community/pending/approve", "POST"),
  Endpoint.new("/multi", "GET"),
  Endpoint.new("/multi", "POST"),
  Endpoint.new("/page-{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/rust/actix_builder/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_actix_web"),
}).perform_tests
