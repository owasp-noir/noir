require "../../func_spec.cr"

# Regression: full-stack-fastapi-template style `prefix=API_PREFIX` where
# the local alias points at `settings.API_V1_STR`. The resolver follows the
# local assignment, then the imported BaseSettings instance, and prefixes
# routes with the literal value instead of emitting garbage expression URLs.
expected_endpoints = [
  Endpoint.new("/api/v1/login/access-token", "POST"),
  Endpoint.new("/api/v1/login/test-token", "POST"),
  # `APIRouter(prefix="/items")` — the router's own prefix must
  # be preserved when the parent (api_router) layers `/api/v1`
  # via `settings.API_V1_STR` on top, yielding `/api/v1/items/`.
  Endpoint.new("/api/v1/items/", "GET"),
  Endpoint.new("/api/v1/items/{id}", "GET", [Param.new("id", "", "path")]),
  # Simple f-string prefixes with resolvable constants should keep
  # their concrete segment instead of being dropped or emitted raw.
  Endpoint.new("/api/v1/dynamic/v1/probe", "GET"),
  # fastapi-realworld style local settings factory:
  # `settings = get_app_settings(); prefix=settings.api_prefix`.
  Endpoint.new("/factory/probe", "GET"),
]

FunctionalTester.new("fixtures/python/fastapi_settings_prefix/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
