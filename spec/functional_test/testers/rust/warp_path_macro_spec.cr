require "../../func_spec.cr"

# warp's `path!` macro (literal + typed segments) and filter-returning
# helper functions whose tail expression IS the route. A non-route
# helper filter (`with_auth`, no path) must not become an endpoint.
expected_endpoints = [
  Endpoint.new("/hello/from/warp", "GET"),
  Endpoint.new("/sum/:param1/:param2", "GET", [
    Param.new("param1", "", "path"),
    Param.new("param2", "", "path"),
  ]),
  Endpoint.new("/todos", "GET"),
  Endpoint.new("/todos", "POST"),
  Endpoint.new("/todos/:param", "PUT", [
    Param.new("param", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/rust/warp_path_macro/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_warp"),
}).perform_tests
