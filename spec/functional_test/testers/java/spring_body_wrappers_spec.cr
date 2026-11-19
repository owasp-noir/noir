require "../../func_spec.cr"

line_params = [Param.new("sku", "", "json"), Param.new("quantity", "", "json")]

# A body read through `Mono`/`Flux` or handed over as `HttpEntity`/`RequestEntity`
# binds the element type's fields, like a plain or `List<T>` body.
expected_endpoints = [
  Endpoint.new("/java/orders/control", "POST", line_params),
  Endpoint.new("/java/orders/control-list", "POST", line_params),
  Endpoint.new("/java/orders/mono", "POST", line_params),
  Endpoint.new("/java/orders/flux", "POST", line_params),
  Endpoint.new("/java/orders/http-entity", "POST", line_params),
  Endpoint.new("/java/orders/request-entity", "POST", line_params),
]

FunctionalTester.new("fixtures/java/spring_body_wrappers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
