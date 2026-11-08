require "../../func_spec.cr"

# An unused `FastAPI()` app in a parent directory (`service/main.py`) must
# not hide `service/app/main.py`'s `/api` prefix, nor the Pydantic body
# model `routes.py` imports from `app.schemas`.
expected_endpoints = [
  Endpoint.new("/api/items", "POST", [
    Param.new("name", "", "json"),
    Param.new("price", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/python/fastapi_shallow_root/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
