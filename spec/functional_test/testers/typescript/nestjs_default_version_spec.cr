require "../../func_spec.cr"

# `enableVersioning({ type: URI, prefix: `${CONTEXT_PATH}v`, defaultVersion: '1' })`
# in apps/api: a controller with no version of its own serves `/v1`, one
# with `version: '2'` serves `/v2`, VERSION_NEUTRAL none. The context path
# is the deployment's (empty unless configured). apps/webhook has its own
# bootstrap with no versioning, so its hard-coded `v1/` is not doubled.
expected_endpoints = [
  Endpoint.new("/v1/auth/login", "POST", [Param.new("body", "", "body")]),
  Endpoint.new("/v2/topics", "GET"),
  Endpoint.new("/.well-known/resource", "GET"),
  Endpoint.new("/v1/health-check", "GET"),
]

FunctionalTester.new("fixtures/typescript/nestjs_default_version/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
