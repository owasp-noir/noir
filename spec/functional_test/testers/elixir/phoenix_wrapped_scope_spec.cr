require "../../func_spec.cr"

# `scope "/api", # v1` with the module alias on the next line: the opener
# was read one line at a time, so the alias was dropped and the bare
# `UserController` resolved to every controller of that name.
FunctionalTester.new("fixtures/elixir/phoenix_wrapped_scope/", {
  :techs     => 1,
  :endpoints => 3,
}, [
  Endpoint.new("/api/users", "GET", [Param.new("api_q", "", "query")]),
  Endpoint.new("/admin/users", "GET", [Param.new("admin_q", "", "query")]),
  Endpoint.new("/users", "GET", [Param.new("root_q", "", "query")]),
]).perform_tests

describe "Phoenix wrapped scope module", tags: "functional" do
  it "resolves each route to its own scope's controller only" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/elixir/phoenix_wrapped_scope/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    app.endpoints.each do |endpoint|
      endpoint.params.size.should eq(1)
    end
  end
end
