require "../../func_spec.cr"

describe "--ai-context on Express auth fixtures", tags: "functional" do
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
    endpoints.size.should eq(25)

    # The handler lives in routes/search.js: the route carries that body's
    # query param, its callees (with the handler file as their path) and the
    # sql sink built there, not just the `app.get(...)` line in server.js.
    search = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/rest/products/search" }
    search.params.map { |p| {p.name, p.param_type} }.should eq([{"q", "query"}])
    search.callees.map(&.name).should contain("models.sequelize.query().then().catch")
    search.callees.first.path.should_not(be_nil).should end_with("express_auth/routes/search.js")
    search.ai_context.should_not(be_nil).sinks.map(&.kind).should contain("sql")

    # `app.use('/ftp/:file', servePublicFiles())`: the mounted definition
    # answers the request itself, so it is a route under every method.
    ftp = endpoints.select { |ep| ep.url == "/ftp/:file" }
    ftp.map(&.method).sort!.should eq(%w[DELETE GET HEAD OPTIONS PATCH POST PUT])
    ftp.first.handler.try(&.name).should eq("servePublicFiles()")
    ftp.first.callees.map(&.name).should contain("res.sendFile")
    # It answers 403 to a bad file name, but it is the handler, not a guard.
    ftp.first.ai_context.should_not(be_nil).guards.should be_empty

    # A path-mounted guard or rate limiter is not a route: the mount only
    # guards the routes declared under it.
    endpoints.count { |ep| ep.url == "/rest/basket" }.should eq(0)
    # A router factory on a path is the prefix of its own routes, not a route.
    endpoints.count { |ep| ep.url == "/legacy" }.should eq(0)
    endpoints.count { |ep| ep.url == "/legacy/:gid" }.should eq(1)
    endpoints.count { |ep| ep.url == "/rest/user/reset-password" }.should eq(0)
    endpoints.count { |ep| ep.url == "/rest/user/authentication-details" }.should eq(1)

    public_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/public" }.ai_context
    public_context = public_context.should_not be_nil
    public_context.guards.should be_empty

    profile_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/profile" }.ai_context
    profile_context = profile_context.should_not be_nil
    profile_context.guards.size.should eq(1)
    profile_context.guards[0].source.should eq("express_auth")
    profile_context.guards[0].confidence.should_not be_nil
    profile_context.callees.map(&.name).should contain("res.json")
    profile_context.callees.find!(&.name.==("res.json")).confidence.should_not be_nil

    post_context = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/api/data" }.ai_context
    post_context = post_context.should_not be_nil
    post_context.guards.size.should eq(1)
    post_context.signals.map(&.kind).should contain("state_change")

    health_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/health" }.ai_context
    health_context = health_context.should_not be_nil
    health_context.guards.should be_empty

    # A middleware the tagger knows only by definition: the guard is named,
    # and a route whose only argument is the guard has no handler.
    users = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/Users" }
    users.handler.should be_nil
    users.callees.should be_empty
    users.ai_context.should_not(be_nil).guards.map(&.name).should eq(["Express security.isAuthorized() (expressjwt) middleware"])

    user_put = endpoints.find! { |ep| ep.method == "PUT" && ep.url == "/api/Users/:id" }
    user_put.handler.should be_nil
    user_put.callees.should be_empty
    user_put.ai_context.should_not(be_nil).guards.map(&.name).should eq(["Express security.denyAll() (expressjwt) middleware"])

    login = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/rest/user/login" }
    login.handler.try(&.name).should eq("login")
    login.ai_context.should_not(be_nil).guards.should be_empty
  end
end
