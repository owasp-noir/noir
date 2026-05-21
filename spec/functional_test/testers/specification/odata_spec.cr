require "../../func_spec.cr"

query_params = [
  Param.new("$filter", "", "query"),
  Param.new("$select", "", "query"),
  Param.new("$expand", "", "query"),
  Param.new("$top", "", "query"),
  Param.new("$skip", "", "query"),
  Param.new("$orderby", "", "query"),
  Param.new("$count", "", "query"),
  Param.new("$search", "", "query"),
]

product_body = [
  Param.new("ID", "int", "json"),
  Param.new("Name", "string", "json"),
  Param.new("Price", "number", "json"),
]

user_body = [
  Param.new("ID", "int", "json"),
  Param.new("Email", "string", "json"),
]

expected_endpoints = [
  Endpoint.new("/Products", "GET", query_params),
  Endpoint.new("/Products", "POST", product_body),
  Endpoint.new("/Products({key})", "GET", [Param.new("key", "", "path")]),
  Endpoint.new("/Products({key})", "PATCH", [Param.new("key", "", "path")] + product_body),
  Endpoint.new("/Products({key})", "DELETE", [Param.new("key", "", "path")]),
  Endpoint.new("/Me", "GET", [] of Param),
  Endpoint.new("/Me", "PATCH", user_body),
  Endpoint.new("/GetTopProducts(count={count})", "GET", [Param.new("count", "", "path")]),
  Endpoint.new("/RateProduct", "POST", [
    Param.new("ProductID", "", "json"),
    Param.new("Rating", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/odata/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
