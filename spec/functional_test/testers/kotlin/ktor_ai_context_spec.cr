require "../../func_spec.cr"

describe "--ai-context on Ktor auth fixtures" do
  fixture_path = "fixtures/kotlin/ktor_auth/"
  app_suffix = "spec/functional_test/fixtures/kotlin/ktor_auth/src/Application.kt"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "captures authenticate blocks while leaving public Ktor routes unguarded" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints

    public_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/public" }
    public_endpoint.details.code_paths.any? { |info| info.path.ends_with?(app_suffix) && info.line == 10 }.should be_true
    public_context = public_endpoint.ai_context
    public_context = public_context.should_not be_nil
    public_context.guards.should be_empty

    profile_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/profile" }
    profile_endpoint.details.code_paths.any? { |info| info.path.ends_with?(app_suffix) && info.line == 15 }.should be_true
    profile_context = profile_endpoint.ai_context
    profile_context = profile_context.should_not be_nil
    profile_context.guards.size.should eq(1)
    profile_context.guards[0].source.should eq("ktor_auth")
    profile_context.callees.map(&.name).should contain("call.principal")

    post_endpoint = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/api/data" }
    post_endpoint.details.code_paths.any? { |info| info.path.ends_with?(app_suffix) && info.line == 20 }.should be_true
    post_context = post_endpoint.ai_context
    post_context = post_context.should_not be_nil
    post_context.guards.size.should eq(1)
    post_context.signals.map(&.kind).should contain("state_change")

    admin_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/admin/dashboard" }
    admin_endpoint.details.code_paths.any? { |info| info.path.ends_with?(app_suffix) && info.line == 27 }.should be_true
    admin_context = admin_endpoint.ai_context
    admin_context = admin_context.should_not be_nil
    admin_context.guards.size.should eq(1)
    admin_context.guards[0].source.should eq("ktor_auth")

    health_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/health" }
    health_endpoint.details.code_paths.any? { |info| info.path.ends_with?(app_suffix) && info.line == 33 }.should be_true
    health_context = health_endpoint.ai_context
    health_context = health_context.should_not be_nil
    health_context.guards.should be_empty
  end
end
