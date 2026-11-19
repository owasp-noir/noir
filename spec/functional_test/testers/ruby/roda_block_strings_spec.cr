require "../../func_spec.cr"

# A `do` inside a response string (`"There is nothing to do"`) must not
# open a block, or the `r.on "tasks"` prefix stays on every later route.
expected_endpoints = [
  Endpoint.new("/tasks/next", "GET"),
  Endpoint.new("/tasks/list", "GET"),
  Endpoint.new("/users/me", "GET"),
  Endpoint.new("/health", "GET"),
]

FunctionalTester.new("fixtures/ruby/roda_block_strings/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
