require "../../func_spec.cr"

# Stdlib, pydantic and Enum annotations are query values, not dropped
# bodies; classes FastAPI injects (Response, BackgroundTasks) are not params.
expected_endpoints = [
  Endpoint.new("/orders", "GET", %w[customer_id start end min_total status order kind level color limit page q].map { |name| Param.new(name, "", "query") }),
  Endpoint.new("/items", "POST", [Param.new("name", "", "json")]),
]

FunctionalTester.new("fixtures/python/fastapi_query_value_types/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
