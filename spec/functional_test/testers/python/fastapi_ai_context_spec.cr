require "../../func_spec.cr"

describe "--ai-context on FastAPI auth fixtures", tags: "functional" do
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
    admin_context.guards.map(&.kind).should_not contain("authz_guard")
    admin_context.signals.map(&.kind).should_not contain("sensitive_response")

    public_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/public" }.ai_context
    public_context = public_context.should_not be_nil
    public_context.guards.should be_empty

    # A superuser dependency and an inline ownership 403 are authorization,
    # so neither row is an authz_absence; a bare get_current_user still is.
    superuser_context = endpoints.find! { |ep| ep.method == "DELETE" && ep.url == "/users/{user_id}" }.ai_context.should_not be_nil
    superuser_context.guards.map(&.kind).should eq(["auth_guard", "authz_guard"])
    superuser_context.signals.map(&.kind).should_not contain("authz_absence")

    ownership_context = endpoints.find! { |ep| ep.method == "PUT" && ep.url == "/items/{item_id}" }.ai_context.should_not be_nil
    ownership_context.guards.map(&.kind).should eq(["auth_guard", "authz_guard"])
    ownership_context.signals.map(&.kind).should_not contain("authz_absence")

    plain_context = endpoints.find! { |ep| ep.method == "PATCH" && ep.url == "/notes/{note_id}" }.ai_context.should_not be_nil
    plain_context.guards.map(&.kind).should eq(["auth_guard"])
    plain_context.signals.map(&.kind).should contain("authz_absence")
  end
end
