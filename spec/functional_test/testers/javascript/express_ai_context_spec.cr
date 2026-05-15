require "../../func_spec.cr"

describe "--ai-context on Express auth fixtures" do
  fixture_path = "fixtures/javascript/express_auth/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "keeps guard detections route-local and still enriches protected handlers" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints
    endpoints.size.should eq(5)

    public_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/public" }.ai_context
    public_context = public_context.should_not be_nil
    public_context.guards.should be_empty

    profile_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/profile" }.ai_context
    profile_context = profile_context.should_not be_nil
    profile_context.guards.size.should eq(1)
    profile_context.guards[0].source.should eq("express_auth")
    profile_context.callees.map(&.name).should contain("res.json")

    post_context = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/api/data" }.ai_context
    post_context = post_context.should_not be_nil
    post_context.guards.size.should eq(1)
    post_context.signals.map(&.kind).should contain("state_change")

    health_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/health" }.ai_context
    health_context = health_context.should_not be_nil
    health_context.guards.should be_empty
  end
end
