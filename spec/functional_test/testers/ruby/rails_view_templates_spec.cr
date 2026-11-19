require "../../func_spec.cr"

# A `resources` action the controller does not define is still served when
# `app/views/<controller>/<action>.*` exists; a partial is no template, and
# an action with neither draws nothing.
expected_endpoints = [
  Endpoint.new("/books", "GET"),
  Endpoint.new("/books/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/session/new", "GET"),
  Endpoint.new("/session", "POST", [Param.new("email", "", "form"), Param.new("password", "", "form")]),
  Endpoint.new("/about", "GET"),
]

tester = FunctionalTester.new("fixtures/ruby/rails_view_templates/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "points a template-only action at its template", tags: "functional" do
  paths = tester.app.endpoints.to_h { |ep| {"#{ep.method} #{ep.url}", ep.details.code_paths.first.path} }
  paths["GET /books"].should end_with("app/views/books/index.html.erb")
  paths["GET /session/new"].should end_with("app/views/sessions/new.html.erb")
end
