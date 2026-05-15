require "../../func_spec.cr"

describe "--ai-context on Django auth fixtures" do
  fixture_path = "fixtures/python/django_auth/"
  views_suffix = "spec/functional_test/fixtures/python/django_auth/blog/views.py"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "preserves handler source locations and surfaces Django auth guards only on protected views" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints
    endpoints.size.should eq(7)

    public_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/public/" }
    public_endpoint.details.code_paths.any? { |info| info.path.ends_with?(views_suffix) && info.line == 10 }.should be_true
    public_context = public_endpoint.ai_context
    public_context = public_context.should_not be_nil
    public_context.guards.should be_empty

    list_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/posts/" }
    list_endpoint.details.code_paths.any? { |info| info.path.ends_with?(views_suffix) && info.line == 15 }.should be_true
    list_context = list_endpoint.ai_context
    list_context = list_context.should_not be_nil
    list_context.guards.size.should eq(1)
    list_context.guards[0].source.should eq("django_auth")

    detail_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/posts/<int:pk>/" }
    detail_endpoint.details.code_paths.any? { |info| info.path.ends_with?(views_suffix) && info.line == 24 }.should be_true
    detail_context = detail_endpoint.ai_context
    detail_context = detail_context.should_not be_nil
    detail_context.guards.size.should eq(1)
    detail_context.guards[0].source.should eq("django_auth")

    create_post_endpoint = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/posts/create/" }
    create_post_endpoint.details.code_paths.any? { |info| info.path.ends_with?(views_suffix) && info.line == 20 }.should be_true
    create_post_context = create_post_endpoint.ai_context
    create_post_context = create_post_context.should_not be_nil
    create_post_context.guards.size.should eq(1)
    create_post_context.guards[0].source.should eq("django_auth")
    create_post_context.signals.map(&.kind).should contain("state_change")

    api_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/posts/" }
    api_endpoint.details.code_paths.any? { |info| info.path.ends_with?(views_suffix) && info.line == 32 }.should be_true
    api_context = api_endpoint.ai_context
    api_context = api_context.should_not be_nil
    api_context.guards.size.should eq(1)
    api_context.guards[0].source.should eq("django_auth")
  end
end
