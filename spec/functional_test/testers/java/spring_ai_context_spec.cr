require "../../func_spec.cr"

describe "--ai-context on Spring auth fixtures" do
  fixture_path = "fixtures/java/spring_auth/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "surfaces Spring auth guards on protected handlers only" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints

    admin_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/admin/users" }.ai_context
    admin_context = admin_context.should_not be_nil
    admin_context.guards.map(&.source).should contain("spring_auth")

    delete_context = endpoints.find! { |ep| ep.method == "DELETE" && ep.url == "/api/posts/{id}" }.ai_context
    delete_context = delete_context.should_not be_nil
    delete_context.guards.map(&.source).should contain("spring_auth")
    delete_context.signals.map(&.kind).should contain("path_param")
    delete_context.signals.map(&.kind).should contain("state_change")

    public_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/public/health" }.ai_context
    public_context = public_context.should_not be_nil
    public_context.guards.should be_empty
  end
end
