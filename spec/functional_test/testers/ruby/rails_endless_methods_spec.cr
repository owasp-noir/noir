require "../../func_spec.cr"

# Endless methods: `def index = ...` is an action, and endless helpers
# (`def post_params = params.require(:post).permit(...)`, `def allowed =
# %i[...]`) still supply their permit lists.
expected_endpoints = [
  Endpoint.new("/posts", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/posts", "POST", [Param.new("title", "", "json"), Param.new("body", "", "json")]),
  Endpoint.new("/posts/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/posts/:id", "PUT", [Param.new("id", "", "path"), Param.new("summary", "", "json"), Param.new("tags", "", "json")]),
  Endpoint.new("/posts/:id", "PATCH", [Param.new("id", "", "path"), Param.new("summary", "", "json"), Param.new("tags", "", "json")]),
]

FunctionalTester.new("fixtures/ruby/rails_endless_methods/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
