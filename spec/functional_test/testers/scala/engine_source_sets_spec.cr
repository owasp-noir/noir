require "../../func_spec.cr"

# Specs/Suites under `src/test/` and sbt scripted projects under
# `src/sbt-test/` build route tables nothing serves; only the `src/main`
# routes of each ScalaEngine adapter count.
expected_endpoints = [
  Endpoint.new("/akka-live", "GET"),
  Endpoint.new("/http4s-live", "GET"),
  Endpoint.new("/tapir-live", "GET"),
  Endpoint.new("/zio-live", "GET"),
]

FunctionalTester.new("fixtures/scala/engine_source_sets/", {
  :techs     => 4,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
