require "../../func_spec.cr"

# Gotham verb coverage: a typed-extractor pipeline between the verb and
# `.to` (`.get("/p").with_path_extractor::<T>().to(h)`), the `get_or_head`
# convenience verb, the multi-method `request(vec![Method::GET, ...])`
# form, static `to_file` terminals, and `associate` closures whose inner
# `assoc.<verb>().to(h)` calls register under the associate path.
expected_endpoints = [
  Endpoint.new("/user/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/products", "GET"),
  Endpoint.new("/products", "HEAD"),
  Endpoint.new("/home", "GET"),
  Endpoint.new("/home", "HEAD"),
  Endpoint.new("/doc", "GET"),
  Endpoint.new("/address", "POST"),
  Endpoint.new("/address", "GET"),
]

FunctionalTester.new("fixtures/rust/gotham_verbs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_gotham"),
}).perform_tests
