require "../../func_spec.cr"

describe "--ai-context on FastAPI auth fixtures" do
  fixture_path = "fixtures/python/fastapi_auth/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "captures dependency-based auth while leaving public handlers unguarded" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints

    profile_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/profile" }.ai_context
    profile_context = profile_context.should_not be_nil
    profile_context.guards.size.should eq(1)
    profile_context.guards[0].source.should eq("fastapi_auth")
    profile_context.callees.map(&.name).should contain("Depends")

    admin_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/admin" }.ai_context
    admin_context = admin_context.should_not be_nil
    admin_context.guards.map(&.source).should contain("fastapi_auth")

    public_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/public" }.ai_context
    public_context = public_context.should_not be_nil
    public_context.guards.should be_empty
  end
end
