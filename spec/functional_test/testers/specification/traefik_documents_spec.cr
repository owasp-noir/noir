require "../../func_spec.cr"

# Every document of a multi-document manifest (the first is a Middleware),
# `PathRegexp` / `Path` arguments holding `(...)`, and Swarm `deploy.labels`.
# The regex routes used to collapse to a single `/`.
expected_endpoints = [
  Endpoint.new("/first", "ANY"),
  Endpoint.new("/second", "ANY"),
  Endpoint.new("/api/(v1|v2)/items", "ANY"),
  Endpoint.new("/legacy/{name}", "ANY"),
  Endpoint.new("/swarm-api", "ANY"),
]

FunctionalTester.new("fixtures/specification/traefik_documents/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
