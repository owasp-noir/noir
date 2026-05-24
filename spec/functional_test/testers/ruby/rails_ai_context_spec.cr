require "../../func_spec.cr"

describe "--ai-context on Rails auth fixtures" do
  fixture_path = "fixtures/ruby/rails_auth/"
  controller_suffix = "spec/functional_test/fixtures/ruby/rails_auth/app/controllers/posts_controller.rb"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "preserves controller action lines and respects skip_before_action overrides" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints

    index_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/posts" }
    index_endpoint.details.code_paths.any? { |info| info.path.ends_with?(controller_suffix) && info.line == 5 }.should be_true
    index_context = index_endpoint.ai_context
    index_context = index_context.should_not be_nil
    index_context.guards.should be_empty
    index_endpoint.params.map(&.name).should be_empty
    index_context.signals.map(&.kind).should_not contain("identifier_input")
    index_context.signals.map(&.kind).should_not contain("idor")

    show_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/posts/1" }
    show_endpoint.details.code_paths.any? { |info| info.path.ends_with?(controller_suffix) && info.line == 9 }.should be_true
    show_endpoint.params.map { |param| {param.name, param.param_type} }.should eq([{"id", "path"}])
    show_context = show_endpoint.ai_context
    show_context = show_context.should_not be_nil
    show_context.guards.size.should eq(1)
    show_context.guards[0].source.should eq("ruby_auth")
    show_context.signals.map(&.kind).should contain("path_param")
    show_context.signals.map(&.kind).should_not contain("identifier_input")
    show_context.signals.map(&.kind).should contain("idor")

    create_endpoint = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/posts" }
    create_endpoint.details.code_paths.any? { |info| info.path.ends_with?(controller_suffix) && info.line == 13 }.should be_true
    create_context = create_endpoint.ai_context
    create_context = create_context.should_not be_nil
    # `create` carries two guards: the Devise `authenticate_user!`
    # (an auth_guard) and a Pundit-style `authorize post` line
    # surfaced as an authz_guard. The pair captures the
    # auth-vs-authz distinction explicitly.
    create_context.guards.map(&.kind).sort!.should eq(["auth_guard", "authz_guard"])
    create_context.guards.any? { |g| g.source == "ruby_auth" }.should be_true
    create_endpoint.params.map(&.name).sort!.should eq(["body", "title"])
    create_context.signals.map(&.kind).should contain("state_change")
    create_context.signals.map(&.kind).should_not contain("identifier_input")
    create_context.signals.map(&.kind).should_not contain("idor")
    create_context.validators.map(&.kind).should contain("validation")

    destroy_endpoint = endpoints.find! { |ep| ep.method == "DELETE" && ep.url == "/posts/1" }
    destroy_endpoint.details.code_paths.any? { |info| info.path.ends_with?(controller_suffix) && info.line == 19 }.should be_true
    destroy_context = destroy_endpoint.ai_context
    destroy_context = destroy_context.should_not be_nil
    destroy_context.guards.size.should eq(1)
    destroy_context.guards[0].source.should eq("ruby_auth")
    destroy_endpoint.params.map { |param| {param.name, param.param_type} }.should eq([{"id", "path"}])
    destroy_context.signals.map(&.kind).should contain("path_param")
    destroy_context.signals.map(&.kind).should_not contain("identifier_input")
    destroy_context.signals.map(&.kind).should contain("idor")
    destroy_context.validators.should be_empty
  end
end
