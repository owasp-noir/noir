require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/todos", "GET", [
    Param.new("status", "", "query"),
  ]),
  Endpoint.new("/todos/{todo_id}", "POST", [
    Param.new("todo_id", "", "path"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/search", "GET", [
    Param.new("term", "", "query"),
    Param.new("X-Trace-Id", "", "header"),
  ]),
  Endpoint.new("/search", "POST", [
    Param.new("term", "", "query"),
    Param.new("X-Trace-Id", "", "header"),
  ]),
  # Same-file `Router()` mounted with `include_router(router, prefix="/v1")`.
  Endpoint.new("/v1/admin/users/{uid}", "DELETE", [
    Param.new("uid", "", "path"),
  ]),
  # `from routes import orders` + `include_router(orders.router, prefix=...)`.
  Endpoint.new("/orders/{order_id}", "PUT", [
    Param.new("order_id", "", "path"),
    Param.new("sku", "", "json"),
  ]),
  # Aliased import mounted without a prefix.
  Endpoint.new("/health", "GET"),
  # Positional `route(rule, method)`; positional `include_router(r, prefix)`
  # serving its "/" at the bare prefix.
  Endpoint.new("/legacy", "POST"),
  Endpoint.new("/bulk", "PUT"),
  Endpoint.new("/bulk", "PATCH"),
  Endpoint.new("/v2", "GET"),
]

# The app lives in src/ below the scan root, so `from routes import orders`
# resolves only from the file's own directory. The commented-out
# `include_router(..., prefix="/old")` mounts nothing.
FunctionalTester.new("fixtures/python/aws_lambda_powertools/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
