require "../../func_spec.cr"

# `do`/`end` inside string literals (`desc 'things to do'`, a params
# `desc:`) must not open or close a block, and chained closers
# (`end.compact`, `end.each do`) must close one. Otherwise a resource prefix
# leaks onto every later route, or a params block swallows the routes after
# it.
expected_endpoints = [
  Endpoint.new("/tasks", "GET"),
  Endpoint.new("/users/me", "GET"),
  Endpoint.new("/items/archive", "POST", [Param.new("id", "", "json"), Param.new("mode", "", "json")]),
  Endpoint.new("/items/recent", "GET"),
  Endpoint.new("/reports", "GET"),
  Endpoint.new("/exports", "GET"),
  Endpoint.new("/health", "GET"),
]

FunctionalTester.new("fixtures/ruby/grape_block_strings/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
