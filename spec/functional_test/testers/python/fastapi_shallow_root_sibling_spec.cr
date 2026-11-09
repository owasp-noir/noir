require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/health", "GET"),
]

# An unused `FastAPI()` file in a sibling directory (`legacy/`) must not
# hide `service/app/main.py`'s `/api` prefix. The app also imports a
# shared library from the repository root (`shared/`), so its imports
# resolve from two roots at once, as with `PYTHONPATH=.:service`.
FunctionalTester.new("fixtures/python/fastapi_shallow_root_sibling/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
