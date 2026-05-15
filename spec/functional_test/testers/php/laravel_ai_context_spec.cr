require "../../func_spec.cr"

describe "--ai-context on Laravel auth fixtures" do
  fixture_path = "fixtures/php/laravel_auth/"
  routes_suffix = "spec/functional_test/fixtures/php/laravel_auth/routes/web.php"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "keeps route middleware guards on protected Laravel routes only" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints
    endpoints.size.should eq(3)
    endpoints.all? { |ep| ep.details.technology == "php_laravel" }.should be_true

    public_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/public" }
    public_endpoint.details.code_paths.any? { |info| info.path.ends_with?(routes_suffix) && info.line == 5 }.should be_true
    public_context = public_endpoint.ai_context
    public_context = public_context.should_not be_nil
    public_context.guards.should be_empty

    profile_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/profile" }
    profile_endpoint.details.code_paths.any? { |info| info.path.ends_with?(routes_suffix) && info.line == 9 }.should be_true
    profile_context = profile_endpoint.ai_context
    profile_context = profile_context.should_not be_nil
    profile_context.guards.size.should eq(1)
    profile_context.guards[0].source.should eq("php_auth")
    profile_context.callees.map(&.name).should contain("response")

    posts_endpoint = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/posts" }
    posts_endpoint.details.code_paths.any? { |info| info.path.ends_with?(routes_suffix) && info.line == 13 }.should be_true
    posts_context = posts_endpoint.ai_context
    posts_context = posts_context.should_not be_nil
    posts_context.guards.size.should eq(1)
    posts_context.guards[0].source.should eq("php_auth")
    posts_context.signals.map(&.kind).should contain("state_change")
  end
end
