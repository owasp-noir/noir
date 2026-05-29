require "../../func_spec.cr"

# Regression test for #1357: Rails app nested under App/ should still
# yield routes when -b points at the repo root. Before the fix the
# analyzer dereferenced @base_path/config/routes.rb directly and got
# zero route-derived endpoints.
expected_endpoints = [
  Endpoint.new("/secret.html", "GET"),
  Endpoint.new("/posts", "GET"),
  Endpoint.new("/posts/1", "GET", [
    Param.new("X-API-KEY", "", "header"),
  ]),
  Endpoint.new("/posts", "POST", [
    Param.new("title", "", "json"),
    Param.new("context", "", "json"),
  ]),
  Endpoint.new("/posts/1", "PUT"),
  Endpoint.new("/posts/1", "PATCH"),
  Endpoint.new("/posts/1", "DELETE"),
  Endpoint.new("/up", "GET"),
]

FunctionalTester.new("fixtures/ruby/rails_monorepo/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
