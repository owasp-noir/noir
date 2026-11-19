require "../../func_spec.cr"

# The one-line rackup `map('/users') { run UsersController }` mounts the
# class under its prefix, like the `map "/posts" do ... end` form.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/posts/:id", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/ruby/sinatra_rackup_map/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
