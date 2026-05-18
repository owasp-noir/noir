require "../../func_spec.cr"

# Regression: full-stack-fastapi-template style `prefix=settings.API_V1_STR`.
# The expression is an attribute reference on an imported BaseSettings
# instance — not a string literal. Before fix #1568 the analyzer used the
# raw expression text as the prefix and emitted garbage URLs like
# `/settings.API_V1_STR/login/access-token`. The resolver now follows the
# import edge into `app/core/config.py`, finds `API_V1_STR: str = "/api/v1"`,
# and prefixes routes with the literal value.
expected_endpoints = [
  Endpoint.new("/api/v1/login/access-token", "POST"),
  Endpoint.new("/api/v1/login/test-token", "POST"),
  # `APIRouter(prefix="/items")` — the router's own prefix must
  # be preserved when the parent (api_router) layers `/api/v1`
  # via `settings.API_V1_STR` on top, yielding `/api/v1/items/`.
  Endpoint.new("/api/v1/items/", "GET"),
  Endpoint.new("/api/v1/items/{id}", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/python/fastapi_settings_prefix/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
