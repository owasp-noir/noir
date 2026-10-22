require "../../func_spec.cr"

# package-benchmark keeps its targets in a `Benchmarks/` directory beside a
# Package.swift (the scan base's or a nested package's), and those workloads
# are not served. A `Benchmarks/` folder inside application sources, such as
# `Sources/App/Controllers/Benchmarks/`, is ordinary code with real routes.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/benchmarks", "GET"),
  Endpoint.new("/inner", "GET"),
]

FunctionalTester.new("fixtures/swift/vapor_benchmarks_names/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("swift_vapor"),
}).perform_tests
