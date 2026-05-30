require "../../func_spec.cr"

# Regression for deep router-prefix inheritance the way real FastAPI
# apps (fastapi-realworld-example-app, Netflix/dispatch) wire it:
#
#   * `from app.api import router as api_router` — an ALIASED router
#     import. The target module registers the router under its original
#     symbol (`router`); the alias must be translated back or the whole
#     sub-tree's prefixes are dropped.
#   * `from app.items import api as items` then `include_router(items.router)`
#     — a MODULE-alias re-export that has to resolve to app/items/api.py.
#   * `router.include_router(secure_router)` where `secure_router` is a
#     LOCAL router carrying its own constructor prefix and itself
#     including another local router — every level must inherit `/api`.
expected_endpoints = [
  Endpoint.new("/api/ping", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/api/users/profile", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/api/items/{item_id}", "GET", [Param.new("item_id", "", "path")]),
  Endpoint.new("/api/secure/admin/dashboard", "GET"),
  # `@router.get("")` on the `/users`-prefixed router resolves to the
  # prefix with no trailing slash (Router.join empty-path handling).
  Endpoint.new("/api/users", "GET"),
]

FunctionalTester.new("fixtures/python/fastapi_nested_routers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
