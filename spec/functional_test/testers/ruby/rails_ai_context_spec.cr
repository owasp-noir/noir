require "../../func_spec.cr"

describe "--ai-context on Rails auth fixtures", tags: "functional" do
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
    index_endpoint.details.code_paths.any? { |info| info.path.ends_with?(controller_suffix) && info.line == 6 }.should be_true
    index_context = index_endpoint.ai_context
    index_context = index_context.should_not be_nil
    index_context.guards.should be_empty
    # ApplicationController's `before_action :authenticate_user` reads the
    # header; `skip_before_action :authenticate_user!` drops a different callback.
    index_endpoint.params.map { |param| {param.name, param.param_type} }.should eq([{"Authorization", "header"}])
    index_context.signals.map(&.kind).should_not contain("identifier_input")
    index_context.signals.map(&.kind).should_not contain("idor")

    show_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/posts/1" }
    show_endpoint.details.code_paths.any? { |info| info.path.ends_with?(controller_suffix) && info.line == 10 }.should be_true
    show_endpoint.params.map { |param| {param.name, param.param_type} }.should eq([{"id", "path"}, {"Authorization", "header"}])
    show_context = show_endpoint.ai_context
    show_context = show_context.should_not be_nil
    show_context.guards.size.should eq(1)
    show_context.guards[0].source.should eq("ruby_auth")
    show_context.signals.map(&.kind).should contain("path_param")
    show_context.signals.map(&.kind).should_not contain("identifier_input")
    show_context.signals.map(&.kind).should contain("idor")

    create_endpoint = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/posts" }
    create_endpoint.details.code_paths.any? { |info| info.path.ends_with?(controller_suffix) && info.line == 14 }.should be_true
    create_context = create_endpoint.ai_context
    create_context = create_context.should_not be_nil
    # `create` carries two guards: the Devise `authenticate_user!`
    # (an auth_guard) and a Pundit-style `authorize post` line
    # surfaced as an authz_guard. The pair captures the
    # auth-vs-authz distinction explicitly.
    create_context.guards.map(&.kind).sort!.should eq(["auth_guard", "authz_guard"])
    create_context.guards.any? { |g| g.source == "ruby_auth" }.should be_true
    create_endpoint.params.map(&.name).sort!.should eq(["Authorization", "body", "title"])
    create_context.signals.map(&.kind).should contain("state_change")
    create_context.signals.map(&.kind).should_not contain("identifier_input")
    create_context.signals.map(&.kind).should_not contain("idor")
    create_context.validators.map(&.kind).should contain("validation")

    destroy_endpoint = endpoints.find! { |ep| ep.method == "DELETE" && ep.url == "/posts/1" }
    destroy_endpoint.details.code_paths.any? { |info| info.path.ends_with?(controller_suffix) && info.line == 20 }.should be_true
    destroy_context = destroy_endpoint.ai_context
    destroy_context = destroy_context.should_not be_nil
    # Devise authenticate + before_action :authorize → auth_guard + authz_guard
    destroy_context.guards.map(&.kind).sort!.should eq(["auth_guard", "authz_guard"])
    destroy_context.guards.any? { |g| g.source == "ruby_auth" }.should be_true
    destroy_context.signals.map(&.kind).should_not contain("authz_absence")
    destroy_endpoint.params.map { |param| {param.name, param.param_type} }.should eq([{"id", "path"}, {"Authorization", "header"}])
    destroy_context.signals.map(&.kind).should contain("path_param")
    destroy_context.signals.map(&.kind).should_not contain("identifier_input")
    destroy_context.signals.map(&.kind).should contain("idor")
    destroy_context.validators.should be_empty

    # ApplicationController's `before_action :authenticate_user` only
    # decodes a token when one is sent: no guard on the public actions.
    articles_index = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/articles" }
    articles_index.ai_context.should_not be_nil
    articles_index.ai_context.not_nil!.guards.should be_empty

    # `get :feed, on: :collection` has routes.rb as its only code path; the
    # `before_action :authenticate_user!, except: [:index, :show]` is read
    # through the resolved handler.
    feed_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/articles/feed" }
    feed_endpoint.details.code_paths.all?(&.path.ends_with?("config/routes.rb")).should be_true
    feed_context = feed_endpoint.ai_context
    feed_context = feed_context.should_not be_nil
    feed_context.guards.map(&.kind).should eq(["auth_guard"])
    feed_context.guards[0].source.should eq("ruby_auth")

    # Callback reads follow the chain each action actually runs: the
    # inherited `authenticate_user` is skipped except on show, and
    # `track_client` (env / fetch / signed cookie) runs only on index.
    clients_index = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/clients" }
    clients_index.params.map { |param| {param.name, param.param_type} }.should eq([
      {"X-Client-Id", "header"}, {"X-Api-Version", "header"}, {"session_hint", "cookie"},
    ])
    clients_show = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/clients/1" }
    clients_show.params.map { |param| {param.name, param.param_type} }.should eq([{"id", "path"}, {"Authorization", "header"}])
  end
end
