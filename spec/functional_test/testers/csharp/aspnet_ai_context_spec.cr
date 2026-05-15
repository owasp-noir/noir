require "../../func_spec.cr"

describe "--ai-context on ASP.NET auth fixtures" do
  fixture_path = "fixtures/csharp/aspnet_auth/"
  controller_suffix = "spec/functional_test/fixtures/csharp/aspnet_auth/Controllers/PostsController.cs"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "surfaces class-level and method-level authorize attributes while respecting AllowAnonymous" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints

    public_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/Posts" }
    public_endpoint.details.code_paths.any? { |info| info.path.ends_with?(controller_suffix) && info.line == 13 }.should be_true
    public_context = public_endpoint.ai_context
    public_context = public_context.should_not be_nil
    public_context.guards.should be_empty

    show_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/Posts/{id}" }
    show_endpoint.details.code_paths.any? { |info| info.path.ends_with?(controller_suffix) && info.line == 19 }.should be_true
    show_context = show_endpoint.ai_context
    show_context = show_context.should_not be_nil
    show_context.guards.size.should eq(1)
    show_context.guards[0].source.should eq("aspnet_auth")
    show_context.signals.map(&.kind).should contain("path_param")

    create_endpoint = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/api/Posts" }
    create_endpoint.details.code_paths.any? { |info| info.path.ends_with?(controller_suffix) && info.line == 26 }.should be_true
    create_context = create_endpoint.ai_context
    create_context = create_context.should_not be_nil
    create_context.guards.size.should eq(1)
    create_context.guards[0].source.should eq("aspnet_auth")
    create_context.signals.map(&.kind).should contain("state_change")
  end
end
