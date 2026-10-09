require "../../func_spec.cr"

# thunderclient.json (legacy flat array) + collections/tc_col_orders.json
# (newer per-collection file). thunderCollection.json holds only collection
# metadata and config/requests.json sits outside `thunder-tests/`; neither
# may contribute endpoints.
expected_endpoints = [
  Endpoint.new("/users", "GET", [
    Param.new("page", "1", "query"),
    Param.new("limit", "20", "query"),
    Param.new("Accept", "application/json", "header"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("Authorization", "", "header"),
    Param.new("name", "bob", "json"),
    Param.new("age", "", "json"),
  ]),
  Endpoint.new("/orders/:orderId", "PUT", [
    Param.new("orderId", "42", "path"),
    Param.new("Authorization", "", "header"),
    Param.new("status", "shipped", "form"),
  ]),
  Endpoint.new("/orders/invoice", "POST", [
    Param.new("orderId", "42", "form"),
    Param.new("invoice", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/specification/thunder_client/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
