require "../../func_spec.cr"

# `test/` and `perf-test/` trees and `foo_test.clj` files hold test handlers
# and router micro-benchmarks nothing serves; `contest/` is not a test tree.
expected_endpoints = [
  Endpoint.new("/compojure-live", "GET"),
  Endpoint.new("/reitit-live", "GET"),
  Endpoint.new("/ring-live", "GET"),
  Endpoint.new("/ring-contest-live", "GET"),
  Endpoint.new("/pedestal-live", "GET"),
]

FunctionalTester.new("fixtures/clojure/test_trees/", {
  :techs     => 4,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
