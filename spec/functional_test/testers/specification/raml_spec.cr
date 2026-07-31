require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users/{userId}", "GET", [
    Param.new("userId", "", "path"),
    Param.new("userId", "", "query"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/raml/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

nested_endpoints = [
  Endpoint.new("/v1/pets", "GET", [
    Param.new("filter", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/v1/pets", "POST", [
    Param.new("name", "", "json"),
    Param.new("breed", "", "json"),
  ]),
  Endpoint.new("/v1/pets/{petId}", "GET", [
    Param.new("petId", "", "path"),
    Param.new("X-Trace-Id", "", "header"),
  ]),
  Endpoint.new("/v1/pets/{petId}/avatar", "POST", [
    Param.new("petId", "", "path"),
    Param.new("file", "", "form"),
    Param.new("caption", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/specification/raml_nested/", {
  :techs     => 1,
  :endpoints => nested_endpoints.size,
}, nested_endpoints).perform_tests

# RAML reserves `{version}` in `baseUri` for the root `version` property, so
# `baseUri: https://api.example.com/api/{version}` with `version: v2` is served
# at `/api/v2` — and `version` is then no longer a path parameter.
advanced_endpoints = [
  Endpoint.new("/api/v2/users", "GET", [
    Param.new("Authorization", "", "header"),
    Param.new("page", "", "query"),
    Param.new("per_page", "", "query"),
  ]),
  Endpoint.new("/api/v2/users", "POST", [
    Param.new("Authorization", "", "header"),
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
  ]),
  Endpoint.new("/api/v2/users/{userId}", "GET", [
    Param.new("Authorization", "", "header"),
    Param.new("userId", "", "path"),
  ]),
  Endpoint.new("/api/v2/users/{userId}", "PUT", [
    Param.new("Authorization", "", "header"),
    Param.new("name", "", "json"),
    Param.new("status", "", "json"),
    Param.new("userId", "", "path"),
  ]),
  Endpoint.new("/api/v2/users/{userId}", "DELETE", [
    Param.new("Authorization", "", "header"),
    Param.new("userId", "", "path"),
  ]),
  Endpoint.new("/api/v2/users/search", "GET", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/api/v2/reports", "GET", [
    Param.new("from", "", "query"),
    Param.new("to", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/specification/raml_advanced/", {
  :techs     => 1,
  :endpoints => advanced_endpoints.size,
}, advanced_endpoints).perform_tests

# Optional (`name?`) markers and `/regex/` pattern keys are not real
# parameter names, and an annotated `baseUri` carries the URL under a
# `value:` key. Each of these used to leak into the output.
optional_endpoints = [
  Endpoint.new("/v1/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("page", "", "query"),
    Param.new("If-None-Match", "", "header"),
  ]),
  Endpoint.new("/v1/search", "POST", [
    Param.new("name", "", "json"),
    Param.new("nickname", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/raml_optional/", {
  :techs     => 1,
  :endpoints => optional_endpoints.size,
}, optional_endpoints).perform_tests

# Traits, types and resourceTypes imported through `uses:` are referenced
# as `namespace.Name`. These used to resolve to nothing, dropping every
# parameter behind a library reference.
library_endpoints = [
  Endpoint.new("/items", "GET", [
    Param.new("offset", "", "query"),
    Param.new("count", "", "query"),
  ]),
  Endpoint.new("/items", "POST", [
    Param.new("sku", "", "json"),
    Param.new("label", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/raml_library/", {
  :techs     => 1,
  :endpoints => library_endpoints.size,
}, library_endpoints).perform_tests

# An Overlay/Extension fragment is applied onto its master API, not served
# standalone. Only the root `api.raml` should yield endpoints; the
# `#%RAML 1.0 Extension` file must not emit a phantom `/products`.
extension_endpoints = [
  Endpoint.new("/v2/products", "GET", [
    Param.new("q", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/specification/raml_extension/", {
  :techs     => 1,
  :endpoints => extension_endpoints.size,
}, extension_endpoints).perform_tests
