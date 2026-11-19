require "../../func_spec.cr"

# A multi-line inline `Mount('/a', routes=[...])` holding both routes and
# another inline Mount: only the nested Mount's routes take its path.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/x01-users/", "GET"),
  Endpoint.new("/x01-users/", "POST"),
  Endpoint.new("/x01-users/{username}/", "GET", [Param.new("username", "", "path")]),
  Endpoint.new("/x01-users/{username}/posts", "GET", [Param.new("username", "", "path")]),
  Endpoint.new("/x01-users/x01-after", "GET"),
  Endpoint.new("/x02-tail", "GET"),
]

FunctionalTester.new("fixtures/python/starlette_mount_nested/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Starlette nested inline Mount", tags: "functional" do
  it "attributes a nested route to its own line, not the Mount's" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/starlette_mount_nested/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    app.endpoints.find! { |ep| ep.url == "/x01-users/x01-after" }.details.code_paths.map(&.line).should eq([30])
  end
end
