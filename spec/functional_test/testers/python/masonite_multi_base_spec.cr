require "../../func_spec.cr"

# Two independent services, each defining its own `ItemController` with
# an `index` action reading a different query input. Confirms controller
# resolution is scoped to the route file's own base path rather than a
# blind project-wide class-name search — without that scoping,
# service_b's route would resolve to service_a's same-named controller.
base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/python/masonite_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/python/masonite_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a-items", "GET", [
    Param.new("region", "", "query"),
  ]),
  Endpoint.new("/b-items", "GET", [
    Param.new("zone", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/python/masonite_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base" => YAML::Any.new(base_paths),
}).perform_tests
