require "../../func_spec.cr"

# `router.get('', …)` is the mount point itself. The parser used to reject
# the empty path outright, so the route was lost both unprefixed (`/`) and
# under a same-file or cross-file mount (`/orders`, `/items`), while
# `post('/')` under the same mount still came out as `/orders/`.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/orders", "GET"),
  Endpoint.new("/orders/", "POST"),
  Endpoint.new("/items", "GET"),
]

FunctionalTester.new("fixtures/javascript/express_empty_path/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
