require "../../func_spec.cr"

# A browser HAR is recorded over HTTP/2, where the request line is re-encoded
# as the `:authority` / `:method` / `:path` / `:scheme` pseudo-headers. Those
# are not parameters any request can set, and neither are `content-length` /
# `host`. A repeated header or cookie is one parameter, not two.
expected_endpoints = [
  Endpoint.new("https://shop.example.com/api/cart", "POST", [
    Param.new("promo", "summer", "query"),
    Param.new("content-type", "application/json", "header"),
    Param.new("x-request-id", "8f2c", "header"),
    Param.new("session", "abc", "cookie"),
    Param.new("sku", "", "json"),
    Param.new("quantity", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/har_http2/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
