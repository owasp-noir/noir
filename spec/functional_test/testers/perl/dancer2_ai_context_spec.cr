require "../../func_spec.cr"

describe "--ai-context on Dancer2 auth fixtures" do
  fixture_path = "fixtures/perl/dancer2_auth/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "surfaces Dancer2 guards, technology, and guard-absence signals" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints

    # require_role wrapper → guard surfaced via the perl_auth tagger.
    admin = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/admin" }
    admin_ctx = admin.ai_context.should_not be_nil
    admin_ctx.guards.should_not be_empty
    admin_ctx.guards.any? { |g| g.source == "perl_auth" }.should be_true
    admin_ctx.signals.any? { |s| s.kind == "technology" && s.name == "perl_dancer2" }.should be_true

    # require_login wrapper.
    me = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/me" }
    me_ctx = me.ai_context.should_not be_nil
    me_ctx.guards.any? { |g| g.source == "perl_auth" }.should be_true

    # logged_in_user inside the handler body.
    dashboard = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/dashboard" }
    dashboard_ctx = dashboard.ai_context.should_not be_nil
    dashboard_ctx.guards.should_not be_empty

    # Unguarded route → no auth guard, and a guard-absence review signal.
    public_ep = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/public" }
    public_ctx = public_ep.ai_context.should_not be_nil
    public_ctx.guards.any? { |g| g.source == "perl_auth" }.should be_false

    # Application-wide `hook before` guard (separate package).
    secret = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/secret" }
    secret_ctx = secret.ai_context.should_not be_nil
    secret_ctx.guards.any? { |g| g.source == "perl_auth" }.should be_true
  end
end
