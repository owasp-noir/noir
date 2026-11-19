require "../../func_spec.cr"

# `resources :photos, :books, :videos` draws every resource it names; a
# hash-rocket option (`:only => [...]`) is not one of them.
expected_endpoints = [
  Endpoint.new("/photos", "GET"),
  Endpoint.new("/photos/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/books", "GET"),
  Endpoint.new("/books/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/videos", "GET"),
  Endpoint.new("/videos/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/profile", "GET"),
  Endpoint.new("/settings", "GET"),
  Endpoint.new("/users", "GET"),
]

FunctionalTester.new("fixtures/ruby/rails_multi_resources/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
