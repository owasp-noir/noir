require "../../func_spec.cr"

# A server stub can list the same file names as a client SDK (`base.ts`,
# `rest.py`, ...) when a custom template emits them, so the client runtime alone
# must not hide its `api/openapi.yaml`: a controller/handler entry in the
# manifest, or a server generator in the sibling `openapitools.json`, keeps the
# served contract. The `axios_client` SDK in the same tree (client runtime, no
# server evidence, a `typescript-axios` generator) is still dropped.
expected_endpoints = [
  Endpoint.new("/cfg-pets", "GET"),
  Endpoint.new("/py-pets", "GET"),
  Endpoint.new("/ts-pets", "GET"),
]

FunctionalTester.new("fixtures/specification/oas_generated_server/", {
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
