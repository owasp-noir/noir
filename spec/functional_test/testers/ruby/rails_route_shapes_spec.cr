require "../../func_spec.cr"

# #3301: `only: []` draws nothing of its own, a slashed `controller:` resolves
# inside the namespace, `resources` in `collection do` drops the parent key,
# and `def patch(*)` in the draw block disables PATCH routes. An endless
# `def` inside `namespace :admin` must not leak a frame (else `/posts` would
# come out as `/admin/posts`).
expected_endpoints = [
  Endpoint.new("/api/v1_alpha/accounts/:account_id/collections", "GET"),
  Endpoint.new("/api/v1/trends", "GET"),
  Endpoint.new("/api/v1/trends/tags", "GET"),
  Endpoint.new("/admin/api", "GET"),
  Endpoint.new("/admin/api/keys", "GET"),
  Endpoint.new("/admin/api/keys/:id", "PUT"),
  Endpoint.new("/posts/:id", "PUT", [Param.new("raw", "", "form")]),
  # `def delete!` and a constraint class's `def get` shadow no mapper verb.
  Endpoint.new("/posts/:id", "DELETE"),
]

FunctionalTester.new("fixtures/ruby/rails_route_shapes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
