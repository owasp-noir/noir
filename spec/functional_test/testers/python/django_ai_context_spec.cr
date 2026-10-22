require "../../func_spec.cr"

describe "--ai-context on Django auth fixtures", tags: "functional" do
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
    endpoints.size.should eq(11)

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

  # The guard is written in the urlconf, not on the view:
  # `path("drafts/", login_required(views.draft_list))` in urls.py and
  # `path("saved/", login_required(self.saved_view.as_view()))` in an
  # AppConfig's `get_urls`. The view file shows no decorator, so the
  # analyzer records the wrapper on the endpoint it builds from that line.
  it "surfaces auth wrappers applied in the urlconf and app config, but not csrf_exempt" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints

    drafts = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/drafts/" }
    drafts.details.code_paths.any? { |info| info.path.ends_with?(views_suffix) && info.line == 36 }.should be_true
    drafts.tags.map(&.description).should eq(["Protected by Django login_required in urlconf"])
    drafts_context = drafts.ai_context.should_not be_nil
    drafts_context.guards.map(&.source).should eq(["django_analyzer"])

    saved = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/shop/saved/" }
    saved.details.code_paths.any? { |info| info.path.ends_with?("django_auth/shop/apps.py") }.should be_true
    saved.tags.map(&.description).should eq(["Protected by Django login_required in urlconf"])
    saved_context = saved.ai_context.should_not be_nil
    saved_context.guards.map(&.source).should eq(["django_analyzer"])

    # A non-auth wrapper is not a guard, and the unwrapped sibling stays open.
    export = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/export/" }
    export.details.code_paths.any? { |info| info.path.ends_with?(views_suffix) && info.line == 40 }.should be_true
    export.ai_context.should_not(be_nil).guards.should be_empty
    summary = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/shop/" }
    summary.ai_context.should_not(be_nil).guards.should be_empty
  end
end
