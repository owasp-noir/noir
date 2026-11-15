require "../../func_spec.cr"

# Absolute imports in each issue table layout must resolve from the project
# root, even when the FastAPI app module is nested several packages deep.
expected_endpoints = [
  Endpoint.new("/api/v1/root/me", "GET"),
  Endpoint.new("/api/v1/shallow/me", "GET"),
  Endpoint.new("/api/v1/shallow-deep/me", "GET"),
  Endpoint.new("/api/v1/auth/me", "GET"),
  Endpoint.new("/api/v1/three/me", "GET"),
]

FunctionalTester.new("fixtures/python/fastapi_nested_app_import/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
