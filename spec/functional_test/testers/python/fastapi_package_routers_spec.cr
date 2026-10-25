require "../../func_spec.cr"

# Prefix chains that run through package `__init__.py` routers:
#
#   * `from app.routes import router` — the router lives in
#     routes/__init__.py, and `from . import auth` then
#     `include_router(auth.router)` names the auth/ package's router.
#     Both used to resolve to no file, so `/api` and `/auth` were lost.
#   * `UserAPIRouter(prefix="")` — a project subclass of APIRouter is a
#     router like APIRouter itself.
expected_endpoints = [
  Endpoint.new("/api/ping", "GET"),
  Endpoint.new("/api/auth/token", "POST"),
  Endpoint.new("/api/auth/refresh", "POST"),
  Endpoint.new("/api/media/validate.txt", "GET"),
]

FunctionalTester.new("fixtures/python/fastapi_package_routers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
