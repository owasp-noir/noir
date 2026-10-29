require "../../func_spec.cr"

describe "Phoenix login that mints a Guardian token", tags: "functional" do
  it "does not guard a 401 login, and still guards a caller check or an EnsureAuthenticated plug" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/elixir/phoenix_login_guard/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints

    guards_of = ->(method : String, url : String) do
      endpoint = endpoints.find! { |e| e.method == method && e.url == url }
      endpoint.ai_context.try(&.guards.map(&.description)) || [] of String
    end

    guards_of.call("POST", "/api/users/login").should be_empty
    guards_of.call("GET", "/api/secret").should eq(["Protected by Phoenix show action check"])
    guards_of.call("POST", "/api/refresh").should eq(["Protected by Phoenix refresh action check"])
    guards_of.call("GET", "/api/private").should eq(["Protected by Phoenix :authenticated pipeline"])
  end
end
