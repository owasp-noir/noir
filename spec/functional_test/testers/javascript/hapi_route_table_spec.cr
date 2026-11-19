require "../../func_spec.cr"

# `server.route(table)` with the table bound by name: a same-file const, a
# module's default export, a named export, and a spread inside the array.
# A table that no `server.route()` receives is not served.
expected_endpoints = [
  Endpoint.new("/control", "GET"),
  Endpoint.new("/local/a", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/local/b", "POST", [Param.new("body", "", "json")]),
  Endpoint.new("/notes", "POST"),
  Endpoint.new("/notes", "GET"),
  Endpoint.new("/notes/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/tasks", "GET"),
  Endpoint.new("/tasks/{id}", "PUT", [Param.new("id", "", "path"), Param.new("body", "", "json")]),
  Endpoint.new("/admin/stats", "GET", [Param.new("x-admin", "", "header")]),
  Endpoint.new("/mixed", "GET"),
]

FunctionalTester.new("fixtures/javascript/hapi_route_table/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Hapi imported route table attribution", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "locates an imported route at its config object" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/hapi_route_table/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    delete = app.endpoints.find! { |ep| ep.method == "DELETE" && ep.url == "/notes/{id}" }
    delete.details.code_paths.first.path.should end_with("src/api/notes.js")
    delete.details.code_paths.first.line.should eq(6)
  end
end
