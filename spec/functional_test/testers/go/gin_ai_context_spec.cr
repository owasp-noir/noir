require "../../func_spec.cr"

describe "--ai-context on Gin auth fixtures" do
  fixture_path = "fixtures/go/gin_auth/"
  main_suffix = "spec/functional_test/fixtures/go/gin_auth/main.go"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "captures group and inline middleware guards while keeping public routes unguarded" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints

    health_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/health" }
    health_endpoint.details.code_paths.any? { |info| info.path.ends_with?(main_suffix) && info.line == 13 }.should be_true
    health_context = health_endpoint.ai_context
    health_context = health_context.should_not be_nil
    health_context.guards.should be_empty

    profile_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/profile" }
    profile_endpoint.details.code_paths.any? { |info| info.path.ends_with?(main_suffix) && info.line == 24 }.should be_true
    profile_context = profile_endpoint.ai_context
    profile_context = profile_context.should_not be_nil
    profile_context.guards.size.should eq(1)
    profile_context.guards[0].source.should eq("go_auth")

    dashboard_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/dashboard" }
    dashboard_endpoint.details.code_paths.any? { |info| info.path.ends_with?(main_suffix) && info.line == 29 }.should be_true
    dashboard_context = dashboard_endpoint.ai_context
    dashboard_context = dashboard_context.should_not be_nil
    dashboard_context.guards.size.should eq(1)
    dashboard_context.guards[0].source.should eq("go_auth")

    admin_endpoint = endpoints.find! { |ep| ep.method == "DELETE" && ep.url == "/admin/users/:id" }
    admin_endpoint.details.code_paths.any? { |info| info.path.ends_with?(main_suffix) && info.line == 34 }.should be_true
    admin_context = admin_endpoint.ai_context
    admin_context = admin_context.should_not be_nil
    admin_context.guards.size.should eq(1)
    admin_context.guards[0].source.should eq("go_auth")
    admin_context.signals.map(&.kind).should contain("state_change")
    admin_signal_kinds = admin_context.signals.map(&.kind)
    admin_signal_kinds.should contain("idor")
    admin_signal_kinds.should_not contain("sqli")
    admin_signal_kinds.should_not contain("ssti")
  end
end
