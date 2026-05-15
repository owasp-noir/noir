require "../../func_spec.cr"

describe "--ai-context on Phoenix auth fixtures" do
  fixture_path = "fixtures/elixir/phoenix_auth/"
  post_suffix = "spec/functional_test/fixtures/elixir/phoenix_auth/lib/myapp_web/controllers/post_controller.ex"
  public_suffix = "spec/functional_test/fixtures/elixir/phoenix_auth/lib/myapp_web/controllers/public_controller.ex"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "preserves controller action paths so Phoenix auth plugs surface end-to-end" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints

    index_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/posts" }
    index_endpoint.details.code_paths.any? { |info| info.path.ends_with?(post_suffix) && info.line == 6 }.should be_true
    index_context = index_endpoint.ai_context
    index_context = index_context.should_not be_nil
    index_context.guards.size.should eq(1)
    index_context.guards[0].source.should eq("elixir_auth")

    show_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/posts/:id" }
    show_endpoint.details.code_paths.any? { |info| info.path.ends_with?(post_suffix) && info.line == 11 }.should be_true
    show_context = show_endpoint.ai_context
    show_context = show_context.should_not be_nil
    show_context.guards.size.should eq(1)
    show_context.guards[0].source.should eq("elixir_auth")
    show_signal_kinds = show_context.signals.map(&.kind)
    show_signal_kinds.should contain("path_param")
    show_signal_kinds.should contain("idor")
    show_signal_kinds.should_not contain("sqli")
    show_signal_kinds.should_not contain("ssti")

    public_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/public" }
    public_endpoint.details.code_paths.any? { |info| info.path.ends_with?(public_suffix) && info.line == 4 }.should be_true
    public_context = public_endpoint.ai_context
    public_context = public_context.should_not be_nil
    public_context.guards.should be_empty
  end
end
