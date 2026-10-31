require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "ExpressAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/javascript/express_auth", __DIR__)
  app_path = "#{fixture_base}/app.js"

  # app.js line reference:
  #  8: app.use('/admin', passport.authenticate('jwt', { session: false }));
  # 11: app.get('/public', (req, res) => {
  # 16: app.get('/profile', passport.authenticate('jwt', { session: false }), (req, res) => {
  # 21: app.post('/api/data', expressjwt({ secret: 'secret', algorithms: ['HS256'] }), (req, res) => {
  # 26: app.get('/dashboard', requireAuth, (req, res) => {
  # 31: app.get('/api/health', (req, res) => {

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects passport.authenticate in route" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(app_path, 16))
    details.technology = "js_express"
    endpoint = Endpoint.new("/profile", "GET", [] of Param, details)

    tagger = ExpressAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("express_auth")
    endpoint.tags[0].description.should contain("Passport")
  end

  it "detects expressjwt middleware" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(app_path, 21))
    details.technology = "js_express"
    endpoint = Endpoint.new("/api/data", "POST", [] of Param, details)

    tagger = ExpressAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("JWT")
  end

  it "detects generic auth middleware (requireAuth)" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(app_path, 26))
    details.technology = "js_express"
    endpoint = Endpoint.new("/dashboard", "GET", [] of Param, details)

    tagger = ExpressAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("requireAuth")
  end

  it "detects ensureLoggedIn / ensureAuthenticated middleware (regression for 'enchure' typo)" do
    noir_options = create_test_options

    tmpdir = File.tempname("express_ensure")
    Dir.mkdir_p(tmpdir)
    js = File.join(tmpdir, "app.js")
    File.write(js, [
      "const express = require('express');",
      "const { ensureLoggedIn } = require('connect-ensure-login');",
      "const app = express();",
      "app.get('/secret', ensureLoggedIn(), (req, res) => {",
      "  res.json({ ok: true });",
      "});",
      "module.exports = app;",
    ].join("\n"))
    noir_options["base"] = YAML::Any.new(tmpdir)

    details = Details.new(PathInfo.new(js, 4))
    details.technology = "js_express"
    endpoint = Endpoint.new("/secret", "GET", [] of Param, details)

    tagger = ExpressAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("ensureLoggedIn")

    FileUtils.rm_rf(tmpdir)
  end

  it "scans auth config under a SECOND base path (multi-root regression)" do
    base1 = File.tempname("express_base1")
    base2 = File.tempname("express_base2")
    Dir.mkdir_p(base1)
    Dir.mkdir_p(base2)
    # app.use auth config lives only under the second base path.
    File.write(File.join(base2, "auth.js"), "app.use('/admin', requireAuth);")
    routes = File.join(base2, "routes.js")
    File.write(routes, [
      "app.get('/admin/panel', (req, res) => {",
      "  res.json({});",
      "});",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new([YAML::Any.new(base1), YAML::Any.new(base2)])

    locator = CodeLocator.instance
    [base1, base2].each do |b|
      Dir.glob("#{b}/**/*").each do |file|
        next if File.directory?(file)
        locator.register_path(file)
      end
    end

    details = Details.new(PathInfo.new(routes, 1))
    details.technology = "js_express"
    endpoint = Endpoint.new("/admin/panel", "GET", [] of Param, details)

    ExpressAuthTagger.new(noir_options).perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("app.use()")

    FileUtils.rm_rf(base1)
    FileUtils.rm_rf(base2)
  end

  it "does not tag unprotected routes" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(app_path, 31))
    details.technology = "js_express"
    endpoint = Endpoint.new("/api/health", "GET", [] of Param, details)

    tagger = ExpressAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "detects app.use level auth for matching prefix" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    # This endpoint has no auth on its own route definition,
    # but /admin prefix has app.use() level auth
    details = Details.new(PathInfo.new(app_path, 31))
    details.technology = "js_express"
    endpoint = Endpoint.new("/admin/settings", "GET", [] of Param, details)

    tagger = ExpressAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("app.use()")
  end

  # --- negative cases: a route that nothing protects must never be tagged ---

  it "does not tag the whole app from a sub-router's own use(auth)" do
    tmpdir = File.tempname("express_subrouter")
    Dir.mkdir_p(File.join(tmpdir, "routes"))

    app_js = File.join(tmpdir, "app.js")
    File.write(app_js, [
      "const express = require('express');",
      "const app = express();",
      "const admin = require('./routes/admin');",
      "app.get('/health', (req, res) => { res.json({ ok: true }); });",
      "app.use('/admin', admin);",
    ].join("\n"))

    admin_js = File.join(tmpdir, "routes", "admin.js")
    File.write(admin_js, [
      "const express = require('express');",
      "const router = express.Router();",
      "router.use(requireAuth);",
      "router.get('/panel', (req, res) => { res.json({ panel: true }); });",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    locator = CodeLocator.instance
    Dir.glob("#{tmpdir}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    health_details = Details.new(PathInfo.new(app_js, 4))
    health_details.technology = "js_express"
    health = Endpoint.new("/health", "GET", [] of Param, health_details)

    panel_details = Details.new(PathInfo.new(admin_js, 4))
    panel_details.technology = "js_express"
    panel = Endpoint.new("/admin/panel", "GET", [] of Param, panel_details)

    ExpressAuthTagger.new(noir_options).perform([health, panel])

    # `router.use(requireAuth)` guards the sub-router, not the application.
    health.tags.empty?.should be_true
    panel.tags.empty?.should be_false
    panel.tags[0].description.should contain("router.use()")

    FileUtils.rm_rf(tmpdir)
  end

  # Chained `route()` links report their own `.get(` / `.post(` line, which
  # names no receiver; the `router.route(` head above it does.
  it "applies router.use() auth to route() chain links reported on their own lines" do
    tmpdir = File.tempname("express_chain_auth")
    Dir.mkdir_p(tmpdir)
    app_js = File.join(tmpdir, "app.js")
    File.write(app_js, [
      "const express = require('express');",          # 1
      "const app = express();",                       # 2
      "const router = express.Router();",             # 3
      "router.use(requireAuth);",                     # 4
      "router.route('/secure')",                      # 5
      "  .get((req, res) => {",                       # 6
      "    res.json({});",                            # 7
      "  })",                                         # 8
      "  .post((req, res) => res.json({}));",         # 9
      "app",                                          # 10
      "  .get('/open', (req, res) => res.json({}));", # 11
      "app.use('/api', router);",                     # 12
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    CodeLocator.instance.register_path(app_js)

    endpoints = [{"GET", "/api/secure", 6}, {"POST", "/api/secure", 9}, {"GET", "/open", 11}].map do |method, url, line|
      details = Details.new(PathInfo.new(app_js, line))
      details.technology = "js_express"
      Endpoint.new(url, method, [] of Param, details)
    end
    ExpressAuthTagger.new(noir_options).perform(endpoints)

    endpoints[0].tags.map(&.name).should eq(["auth"])
    endpoints[1].tags.map(&.name).should eq(["auth"])
    # `app` alone on the line above is not a route() head: receiver unknown.
    endpoints[2].tags.should be_empty

    FileUtils.rm_rf(tmpdir)
  end

  it "does not attribute the next route's middleware to the route above it" do
    tmpdir = File.tempname("express_adjacent")
    Dir.mkdir_p(tmpdir)
    app_js = File.join(tmpdir, "app.js")
    File.write(app_js, [
      "const express = require('express');",
      "const app = express();",
      "app.get('/public/one', (req, res) => { res.json({}); });",
      "app.get('/secret/two', requireAuth, (req, res) => { res.json({}); });",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    locator = CodeLocator.instance
    Dir.glob("#{tmpdir}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    public_details = Details.new(PathInfo.new(app_js, 3))
    public_details.technology = "js_express"
    public_endpoint = Endpoint.new("/public/one", "GET", [] of Param, public_details)

    secret_details = Details.new(PathInfo.new(app_js, 4))
    secret_details.technology = "js_express"
    secret_endpoint = Endpoint.new("/secret/two", "GET", [] of Param, secret_details)

    ExpressAuthTagger.new(noir_options).perform([public_endpoint, secret_endpoint])

    public_endpoint.tags.empty?.should be_true
    secret_endpoint.tags.empty?.should be_false
    secret_endpoint.tags[0].description.should contain("requireAuth")

    FileUtils.rm_rf(tmpdir)
  end

  it "does not let an app.use('/admin') mount guard /administration" do
    tmpdir = File.tempname("express_prefix")
    Dir.mkdir_p(tmpdir)
    app_js = File.join(tmpdir, "app.js")
    File.write(app_js, [
      "const express = require('express');",
      "const app = express();",
      "app.use('/admin', requireAuth);",
      "app.get('/administration/report', (req, res) => { res.json({}); });",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    locator = CodeLocator.instance
    Dir.glob("#{tmpdir}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(app_js, 4))
    details.technology = "js_express"
    endpoint = Endpoint.new("/administration/report", "GET", [] of Param, details)

    ExpressAuthTagger.new(noir_options).perform([endpoint])

    endpoint.tags.empty?.should be_true

    FileUtils.rm_rf(tmpdir)
  end

  it "handles empty code_paths gracefully" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new
    details.technology = "js_express"
    endpoint = Endpoint.new("/unknown/", "GET", [] of Param, details)

    tagger = ExpressAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "does not call a passport login strategy's own route protected" do
    tmpdir = File.tempname("express_passport_login")
    Dir.mkdir_p(tmpdir)
    app_js = File.join(tmpdir, "app.js")
    File.write(app_js, [
      "const app = express();",
      "app.post('/login', passport.authenticate('local', { failureRedirect: '/login' }), (req, res) => res.redirect('/'));",
      "app.get('/auth/github', passport.authenticate('github', { scope: ['user:email'] }));",
      "app.get('/profile', passport.authenticate('jwt', { session: false }), (req, res) => res.json(req.user));",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    CodeLocator.instance.register_path(app_js)

    login = Endpoint.new("/login", "POST", [] of Param, Details.new(PathInfo.new(app_js, 2)))
    github = Endpoint.new("/auth/github", "GET", [] of Param, Details.new(PathInfo.new(app_js, 3)))
    profile = Endpoint.new("/profile", "GET", [] of Param, Details.new(PathInfo.new(app_js, 4)))

    ExpressAuthTagger.new(noir_options).perform([login, github, profile])

    login.tags.should be_empty
    github.tags.should be_empty
    profile.tags.map(&.description).should eq(["Protected by Passport.js jwt strategy"])

    FileUtils.rm_rf(tmpdir)
  end

  # server.js line reference:
  #  8: app.use(security.updateAuthenticatedUsers());            decodes and continues
  # 11: app.use('/rest/basket', security.isAuthorized(), security.appendUserId());
  # 20: app.get('/rest/2fa/status', security.isAuthorized(), asyncHandler(twoFactorStatus));
  # 23: app.post('/rest/2fa/setup',  (rateLimit / security.isAuthorized() / handler on the lines below)
  # 30: app.get('/api/Users', security.isAuthorized());
  # 32:   .get(security.isAuthorized())
  # 36: app.get('/rest/order-history/orders', security.isAccounting(), asyncHandler(listOrders));
  # 39: app.get('/rest/basket/:id', asyncHandler(getBasket));
  # 42: app.post('/rest/user/data-export', security.appendUserId(), asyncHandler(dataExport));
  # 45: app.post('/rest/user/login', login);
  # 49: app.get('/rest/user/authentication-details', asyncHandler(authenticatedUsers()));  mounted guard on 48
  # 52: app.use(security.errorHandler);
  # 53: app.get('/rest/users/list', asyncHandler(authenticatedUsers()));
  describe "middleware resolved to its definition" do
    server_path = "#{fixture_base}/server.js"

    build = ->(method : String, url : String, line : Int32, handler : Handler?) do
      details = Details.new(PathInfo.new(server_path, line))
      details.technology = "js_express"
      endpoint = Endpoint.new(url, method, [] of Param, details)
      endpoint.handler = handler
      endpoint
    end

    run = ->(endpoints : Array(Endpoint)) do
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(fixture_base)
      locator = CodeLocator.instance
      Dir.glob("#{fixture_base}/**/*").each do |file|
        locator.register_path(file) unless File.directory?(file)
      end
      # The resolver follows `./lib/security` inside the scan base and
      # caches what it finds: pin both, since other specs leave theirs.
      previous_bases = locator.scan_base_paths
      locator.scan_base_paths = [fixture_base]
      Noir::JSHandlerResolver.reset
      begin
        ExpressAuthTagger.new(noir_options).perform(endpoints)
      ensure
        locator.scan_base_paths = previous_bases
      end
    end

    it "treats a middleware whose definition can refuse as a guard, wherever it is written" do
      endpoints = run.call([
        build.call("GET", "/rest/2fa/status", 20, nil),
        build.call("POST", "/rest/2fa/setup", 23, nil),
        build.call("GET", "/rest/order-history/orders", 36, nil),
        build.call("GET", "/rest/basket/:id", 39, nil),
        build.call("GET", "/rest/user/authentication-details", 49, nil),
      ])

      endpoints.map { |ep| ep.tags.map(&.description) }.should eq([
        ["Protected by Express security.isAuthorized() (expressjwt) middleware"],
        ["Protected by Express security.isAuthorized() (expressjwt) middleware"],
        ["Protected by Express security.isAccounting() (res.status(403)) middleware"],
        ["Protected by Express security.isAuthorized() (expressjwt) middleware via app.use() on /rest/basket"],
        ["Protected by Express security.isAuthorized() (expressjwt) middleware via app.use() on /rest/user/authentication-details"],
      ])
    end

    it "clears the handler when the guard is the registration's only argument" do
      guard = Handler.new("security.isAuthorized()", "#{fixture_base}/lib/security.js", 7)
      endpoints = run.call([
        build.call("GET", "/api/Users", 30, guard),
        build.call("GET", "/api/Users/:id", 32, guard),
        build.call("GET", "/rest/2fa/status", 20, Handler.new("twoFactorStatus", server_path, 59)),
      ])

      endpoints[0].tags.map(&.name).should eq(["auth"])
      endpoints[0].handler.should be_nil
      endpoints[1].handler.should be_nil
      # A real handler after the guard stays.
      endpoints[2].handler.try(&.name).should eq("twoFactorStatus")
    end

    it "does not count a middleware that only decodes and continues, a handler that answers 401, or an error handler" do
      endpoints = run.call([
        build.call("POST", "/rest/user/data-export", 42, nil),
        build.call("POST", "/rest/user/login", 45, Handler.new("login", server_path, 64)),
        build.call("GET", "/rest/users/list", 53, nil),
      ])

      endpoints.map(&.tags).should eq([[] of Tag, [] of Tag, [] of Tag])
      endpoints[1].handler.try(&.name).should eq("login")
    end
  end

  it "follows middleware arrays and module members to the definition that refuses an anonymous caller" do
    tmpdir = File.tempname("express_mw_arrays")
    Dir.mkdir_p(File.join(tmpdir, "auth"))
    File.write(File.join(tmpdir, "auth", "index.js"), [
      "module.exports = {",
      "  get authenticate() { return require('./authenticate'); },",
      "  get authorize() { return require('./authorize'); },",
      "};",
    ].join("\n"))
    File.write(File.join(tmpdir, "auth", "authenticate.js"), [
      "const authenticate = {",
      "  apiKey(req, res, next) {",
      "    if (!req.headers.authorization) {",
      "      return next();",
      "    }",
      "    return next(new errors.UnauthorizedError({ message: 'bad key' }));",
      "  },",
      "};",
      "module.exports = authenticate;",
    ].join("\n"))
    File.write(File.join(tmpdir, "auth", "authorize.js"), [
      "module.exports = {",
      "  authorizeApi(req, res, next) {",
      "    if (req.user || req.api_key) {",
      "      return next();",
      "    }",
      "    return next(new errors.NoPermissionError({ message: 'no' }));",
      "  },",
      "};",
    ].join("\n"))
    File.write(File.join(tmpdir, "middleware.js"), [
      "const auth = require('./auth');",
      "const tokenCheck = function tokenCheck(req, res, next) {",
      "  if (!req.api_key) {",
      "    return next();",
      "  }",
      "  next(new errors.NoPermissionError({ statusCode: 403 }));",
      "};",
      "function memberGate(req, res, next) {",
      "  if (req.member && req.member.banned) {",
      "    return next(new errors.NoPermissionError({}));",
      "  }",
      "  next();",
      "}",
      "function rejectAnonymous(req, res, next) {",
      "  if (!req.member) {",
      "    return next(new errors.UnauthorizedError({}));",
      "  }",
      "  next();",
      "}",
      "module.exports.privateApi = [auth.authenticate.apiKey, auth.authorize.authorizeApi, tokenCheck];",
      "module.exports.publicApi = [auth.authenticate.apiKey, tokenCheck];",
      "module.exports.memberGate = memberGate;",
      "module.exports.rejectAnonymous = rejectAnonymous;",
    ].join("\n"))
    routes_js = File.join(tmpdir, "routes.js")
    File.write(routes_js, [
      "const mw = require('./middleware');",
      "router.get('/posts', mw.privateApi, http(api.posts.browse));",
      "router.get('/site', mw.publicApi, http(api.site.read));",
      "router.post('/comments', mw.memberGate, http(api.comments.add));",
      "router.put('/member', mw.rejectAnonymous, http(api.member.edit));",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    locator = CodeLocator.instance
    Dir.glob("#{tmpdir}/**/*.js").each { |file| locator.register_path(file) }
    previous_bases = locator.scan_base_paths
    locator.scan_base_paths = [tmpdir]
    Noir::JSHandlerResolver.reset

    endpoints = [
      {"GET", "/posts", 2}, {"GET", "/site", 3}, {"POST", "/comments", 4}, {"PUT", "/member", 5},
    ].map do |method, url, line|
      details = Details.new(PathInfo.new(routes_js, line))
      details.technology = "js_express"
      Endpoint.new(url, method, [] of Param, details)
    end
    begin
      ExpressAuthTagger.new(noir_options).perform(endpoints)
    ensure
      locator.scan_base_paths = previous_bases
      FileUtils.rm_rf(tmpdir)
    end

    endpoints.map { |ep| ep.tags.map(&.description) }.should eq([
      ["Protected by Express mw.privateApi > auth.authorize.authorizeApi (next(new errors.NoPermissionError) middleware"],
      [] of String, # the key check lets a caller without a key through; tokenCheck only screens keys
      [] of String, # refuses only a member who is present
      ["Protected by Express mw.rejectAnonymous (next(new errors.UnauthorizedError) middleware"],
    ])
  end

  it "does not read auth names in path literals or comments as middleware" do
    tmpdir = File.tempname("express_literals")
    Dir.mkdir_p(tmpdir)
    app_js = File.join(tmpdir, "app.js")
    File.write(app_js, [
      "const app = express();",
      "app.get('/oauth/authorize', (req, res) => res.render('consent'));",
      "app.post('/api/verifyToken', (req, res) => res.json({ ok: true }));",
      "app.get('/status', (req, res) => res.send('ok')); // TODO add requireAuth here",
      "app.get('/me', requireAuth, (req, res) => res.json(req.user));",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    CodeLocator.instance.register_path(app_js)

    authorize = Endpoint.new("/oauth/authorize", "GET", [] of Param, Details.new(PathInfo.new(app_js, 2)))
    verify = Endpoint.new("/api/verifyToken", "POST", [] of Param, Details.new(PathInfo.new(app_js, 3)))
    status = Endpoint.new("/status", "GET", [] of Param, Details.new(PathInfo.new(app_js, 4)))
    me = Endpoint.new("/me", "GET", [] of Param, Details.new(PathInfo.new(app_js, 5)))

    ExpressAuthTagger.new(noir_options).perform([authorize, verify, status, me])

    authorize.tags.should be_empty
    verify.tags.should be_empty
    status.tags.should be_empty
    me.tags.map(&.description).should eq(["Protected by Express requireAuth middleware"])

    FileUtils.rm_rf(tmpdir)
  end

  describe "basic auth and reply helpers in a middleware definition" do
    base = File.expand_path("../../../functional_test/fixtures/javascript/express_basic_auth", __DIR__)
    server = "#{base}/server.js"

    it "counts an express-basic-auth middleware (setting-gated) and a helper replying 401, not a status logger" do
      endpoints = [5, 6, 7].map do |line|
        details = Details.new(PathInfo.new(server, line))
        details.technology = "js_express"
        Endpoint.new("/x", "GET", [] of Param, details)
      end
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(base)
      locator = CodeLocator.instance
      Dir.glob("#{base}/**/*").each { |file| locator.register_path(file) unless File.directory?(file) }
      previous_bases = locator.scan_base_paths
      locator.scan_base_paths = [base]
      Noir::JSHandlerResolver.reset
      begin
        ExpressAuthTagger.new(noir_options).perform(endpoints)
      ensure
        locator.scan_base_paths = previous_bases
      end

      endpoints.map { |ep| ep.tags.map(&.description) }.should eq([
        ["Protected by Express apiAuth (expressBasicAuth — a setting can lift it) middleware"],
        ["Protected by Express docsAccess (sendText(res,401) middleware"],
        [] of String,
      ])
    end
  end
end
