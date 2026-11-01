require "../../func_spec.cr"

# `@RestController` mounts under `/rest`, `@PublicApiController` under
# `/api/v1`, `@RootLevelController` at the root. `@Body payload: Dto` (the
# bare form) reads the DTO's `Z.class({...})` fields.
expected_endpoints = [
  Endpoint.new("/rest/login", "POST", [
    Param.new("emailOrLdapLoginId", "", "body"),
    Param.new("password", "", "body"),
    Param.new("mfaCode", "", "body"),
  ]),
  Endpoint.new("/rest/me", "GET"),
  Endpoint.new("/rest/describe", "GET"),
  Endpoint.new("/rest/resolve-signup-token", "GET", [Param.new("query", "", "query")]),
  Endpoint.new("/rest/préférences", "GET"),
  Endpoint.new("/rest/workflows/:workflowId", "GET", [Param.new("workflowId", "", "path")]),
  Endpoint.new("/rest/workflows/public-ping", "GET"),
  Endpoint.new("/rest/workflows/:workflowId", "PATCH", [Param.new("workflowId", "", "path")]),
  Endpoint.new("/rest/workflows/:workflowId", "DELETE", [Param.new("workflowId", "", "path")]),
  Endpoint.new("/api/v1/tags", "GET", [Param.new("query", "", "query")]),
  Endpoint.new("/api/v1/tags/:tagId", "GET", [Param.new("tagId", "", "path")]),
  Endpoint.new("/scim/v2/Users/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/scim/v2/ServiceProviderConfig", "GET"),
]

# `:techs => 2`: `import type { Response } from 'express'` also detects
# js_express, which finds no routes here.
FunctionalTester.new("fixtures/typescript/n8n/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
