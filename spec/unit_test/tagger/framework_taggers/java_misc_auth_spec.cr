require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "JavaMiscAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/java/vertx_auth", __DIR__)
  jwt_path = "#{fixture_base}/JwtController.java"
  dashboard_path = "#{fixture_base}/DashboardController.java"
  profile_path = "#{fixture_base}/ProfileController.java"
  health_path = "#{fixture_base}/HealthController.java"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects Vert.x JWTAuth" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    # Line 9: router.get("/api/secure").handler(ctx -> {
    details = Details.new(PathInfo.new(jwt_path, 9))
    details.technology = "java_vertx"
    endpoint = Endpoint.new("/api/secure", "GET", [] of Param, details)

    tagger = JavaMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("java_misc_auth")
    endpoint.tags[0].description.should contain("JWTAuth")
  end

  it "detects Vert.x BasicAuthHandler" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    # Line 9: router.get("/admin/dashboard").handler(ctx -> {
    details = Details.new(PathInfo.new(dashboard_path, 9))
    details.technology = "java_vertx"
    endpoint = Endpoint.new("/admin/dashboard", "GET", [] of Param, details)

    tagger = JavaMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("AuthHandler")
  end

  it "detects routingContext.user() check" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    # Line 8: router.get("/api/profile").handler(ctx -> {
    details = Details.new(PathInfo.new(profile_path, 8))
    details.technology = "java_vertx"
    endpoint = Endpoint.new("/api/profile", "GET", [] of Param, details)

    tagger = JavaMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("user()")
  end

  it "does not tag unprotected routes" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    # Line 8: router.get("/public/health").handler(ctx -> {
    details = Details.new(PathInfo.new(health_path, 8))
    details.technology = "java_vertx"
    endpoint = Endpoint.new("/public/health", "GET", [] of Param, details)

    tagger = JavaMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "scopes a Vert.x route-level auth handler to the routes under its path" do
    tmpdir = File.tempname("vertx_route_scope")
    Dir.mkdir_p(tmpdir)
    verticle = File.join(tmpdir, "MainVerticle.java")
    File.write(verticle, [
      "import io.vertx.ext.web.handler.RedirectAuthHandler;",                                    # 1
      "public class MainVerticle extends AbstractVerticle {",                                    # 2
      "  public void start() {",                                                                 # 3
      "    router.get(\"/health\").handler(ctx -> ctx.response().end(\"ok\"));",                 # 4
      "    router.route(\"/private/*\").handler(RedirectAuthHandler.create(provider, \"/l\"));", # 5
      "    router.get(\"/private/page\").handler(ctx -> ctx.response().end(\"secret\"));",       # 6
      "    router.get(\"/about\").handler(ctx -> ctx.response().end(\"about\"));",               # 7
      "  }",                                                                                     # 8
      "}",                                                                                       # 9
    ].join("\n"))
    CodeLocator.instance.register_path(verticle)
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    endpoints = {4 => "/health", 6 => "/private/page", 7 => "/about"}.map do |line, url|
      details = Details.new(PathInfo.new(verticle, line))
      details.technology = "java_vertx"
      Endpoint.new(url, "GET", [] of Param, details)
    end
    JavaMiscAuthTagger.new(noir_options).perform(endpoints)
    FileUtils.rm_rf(tmpdir)

    endpoints.map(&.tags.size).should eq([0, 1, 0])
    endpoints[1].tags[0].description.should contain("AuthHandler")
  end

  it "does not read a Vert.x SessionHandler as authentication" do
    tmpdir = File.tempname("vertx_session")
    Dir.mkdir_p(tmpdir)
    verticle = File.join(tmpdir, "MainVerticle.java")
    File.write(verticle, [
      "public class MainVerticle extends AbstractVerticle {",                                # 1
      "  public void start() {",                                                             # 2
      "    router.route().handler(SessionHandler.create(LocalSessionStore.create(vertx)));", # 3
      "    router.get(\"/api/items\").handler(ctx -> ctx.response().end(\"items\"));",       # 4
      "    router.route(\"/private/*\").handler(BasicAuthHandler.create(provider));",        # 5
      "    router.get(\"/private/page\").handler(ctx -> ctx.response().end(\"secret\"));",   # 6
      "  }",                                                                                 # 7
      "}",                                                                                   # 8
    ].join("\n"))
    CodeLocator.instance.register_path(verticle)
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    endpoints = {4 => "/api/items", 6 => "/private/page"}.map do |line, url|
      details = Details.new(PathInfo.new(verticle, line))
      details.technology = "java_vertx"
      Endpoint.new(url, "GET", [] of Param, details)
    end
    JavaMiscAuthTagger.new(noir_options).perform(endpoints)
    FileUtils.rm_rf(tmpdir)

    endpoints[0].tags.should be_empty
    endpoints[1].tags.map(&.description).should eq(["Protected by Vert.x AuthHandler"])
  end

  it "reads a Vert.x route's guards from the routes that cover it, not from nearby lines" do
    tmpdir = File.tempname("vertx_window")
    Dir.mkdir_p(tmpdir)
    verticle = File.join(tmpdir, "MainVerticle.java")
    File.write(verticle, [
      "public class MainVerticle extends AbstractVerticle {",                          # 1
      "  public void start() {",                                                       # 2
      "    JWTAuth jwt = JWTAuth.create(vertx, options);",                             # 3
      "    router.get(\"/api/token\").handler(ctx -> {",                               # 4
      "      ctx.response().end(jwt.generateToken(claims));",                          # 5
      "    });",                                                                       # 6
      "    JWTAuthHandler authHandler = JWTAuthHandler.create(jwt);",                  # 7
      "    router.route(\"/api/*\").handler(authHandler);",                            # 8
      "    router.get(\"/api/items\").handler(ctx -> ctx.response().end(\"items\"));", # 9
      "    router.get(\"/status\").handler(ctx -> ctx.response().end(\"ok\"));",       # 10
      "  }",                                                                           # 11
      "}",                                                                             # 12
    ].join("\n"))
    CodeLocator.instance.register_path(verticle)
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    endpoints = {4 => "/api/token", 9 => "/api/items", 10 => "/status"}.map do |line, url|
      details = Details.new(PathInfo.new(verticle, line))
      details.technology = "java_vertx"
      Endpoint.new(url, "GET", [] of Param, details)
    end
    JavaMiscAuthTagger.new(noir_options).perform(endpoints)
    FileUtils.rm_rf(tmpdir)

    endpoints[0].tags.should be_empty
    endpoints[1].tags.map(&.description).should eq(["Protected by Vert.x AuthHandler"])
    endpoints[2].tags.should be_empty
  end

  it "reads a covering Vert.x registration whose handler sits on the next line" do
    tmpdir = File.tempname("vertx_split")
    Dir.mkdir_p(tmpdir)
    verticle = File.join(tmpdir, "MainVerticle.java")
    File.write(verticle, [
      "public class MainVerticle extends AbstractVerticle {",                          # 1
      "  public void start() {",                                                       # 2
      "    router.route(\"/admin/*\")",                                                # 3
      "        .handler(BasicAuthHandler.create(provider));",                          # 4
      "    router.route(\"/api/*\")",                                                  # 5
      "        .handler(JWTAuthHandler.create(jwt));",                                 # 6
      "    router.get(\"/api/items\").handler(ctx -> ctx.response().end(\"items\"));", # 7
      "    router.get(\"/status\").handler(ctx -> ctx.response().end(\"ok\"));",       # 8
      "  }",                                                                           # 9
      "}",                                                                             # 10
    ].join("\n"))
    CodeLocator.instance.register_path(verticle)
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    endpoints = {7 => "/api/items", 8 => "/status"}.map do |line, url|
      details = Details.new(PathInfo.new(verticle, line))
      details.technology = "java_vertx"
      Endpoint.new(url, "GET", [] of Param, details)
    end
    JavaMiscAuthTagger.new(noir_options).perform(endpoints)
    FileUtils.rm_rf(tmpdir)

    endpoints[0].tags.map(&.description).should eq(["Protected by Vert.x AuthHandler"])
    endpoints[1].tags.should be_empty
  end

  it "reads a Vert.x AuthenticationHandler as authentication" do
    tmpdir = File.tempname("vertx_authn")
    Dir.mkdir_p(tmpdir)
    verticle = File.join(tmpdir, "MainVerticle.java")
    File.write(verticle, [
      "public class MainVerticle extends AbstractVerticle {",                                       # 1
      "  public void start() {",                                                                    # 2
      "    router.post(\"/login\").handler(SimpleAuthenticationHandler.create().authenticate(fn))", # 3
      "      .handler(ctx -> ctx.json(new JsonObject()));",                                         # 4
      "    router.get(\"/status\").handler(ctx -> ctx.response().end(\"ok\"));",                    # 5
      "  }",                                                                                        # 6
      "}",                                                                                          # 7
    ].join("\n"))
    CodeLocator.instance.register_path(verticle)
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    endpoints = {3 => {"/login", "POST"}, 5 => {"/status", "GET"}}.map do |line, (url, verb)|
      details = Details.new(PathInfo.new(verticle, line))
      details.technology = "java_vertx"
      Endpoint.new(url, verb, [] of Param, details)
    end
    JavaMiscAuthTagger.new(noir_options).perform(endpoints)
    FileUtils.rm_rf(tmpdir)

    endpoints[0].tags.map(&.description).should eq(["Protected by Vert.x AuthenticationHandler"])
    endpoints[1].tags.should be_empty
  end

  it "handles empty code_paths gracefully" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new
    details.technology = "java_vertx"
    endpoint = Endpoint.new("/unknown/", "GET", [] of Param, details)

    tagger = JavaMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "returns correct target_techs" do
    JavaMiscAuthTagger.target_techs.should contain("java_vertx")
    JavaMiscAuthTagger.target_techs.should contain("java_armeria")
    JavaMiscAuthTagger.target_techs.should contain("java_jsp")
  end

  # Tag descriptions of the GET routes at the given 1-based lines of a
  # single Vert.x source file.
  vertx_tags = ->(name : String, source : Array(String), routes : Hash(Int32, String)) do
    tmpdir = File.tempname("vertx_case")
    Dir.mkdir_p(tmpdir)
    file = File.join(tmpdir, name)
    File.write(file, source.join("\n"))
    CodeLocator.instance.register_path(file)
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    endpoints = routes.map do |line, url|
      details = Details.new(PathInfo.new(file, line))
      details.technology = "java_vertx"
      Endpoint.new(url, "GET", [] of Param, details)
    end
    JavaMiscAuthTagger.new(noir_options).perform(endpoints)
    FileUtils.rm_rf(tmpdir)
    endpoints.map(&.tags.map(&.description))
  end
  guarded = ["Protected by Vert.x AuthHandler"]

  it "resolves a Vert.x handler held in a method parameter" do
    vertx_tags.call("ApiRoutes.java", [
      "public class ApiRoutes {",
      "  public void mount(Router router, JWTAuthHandler authHandler) {",
      "    router.route(\"/api/*\").handler(authHandler);",
      "    router.get(\"/api/items\").handler(ctx -> ctx.response().end(\"items\"));",
      "  }",
      "}",
    ], {4 => "/api/items"}).should eq([guarded])
  end

  it "resolves a Vert.x handler held in a Kotlin constructor property" do
    vertx_tags.call("ApiRoutes.kt", [
      "class ApiRoutes(private val authHandler: JWTAuthHandler) {",
      "  fun mount(router: Router) {",
      "    router.route(\"/api/*\").handler(authHandler)",
      "    router.get(\"/api/items\").handler { ctx -> ctx.response().end(\"items\") }",
      "  }",
      "}",
    ], {4 => "/api/items"}).should eq([guarded])
  end

  it "resolves a Vert.x handler held in a field assigned elsewhere" do
    vertx_tags.call("ApiRoutes.java", [
      "public class ApiRoutes {",
      "  private final JWTAuthHandler authHandler;",
      "  public ApiRoutes(JWTAuth jwt) {",
      "    this.authHandler = JWTAuthHandler.create(jwt);",
      "  }",
      "  public void mount(Router router) {",
      "    router.route(\"/api/*\").handler(authHandler);",
      "    router.get(\"/api/items\").handler(ctx -> ctx.response().end(\"items\"));",
      "  }",
      "}",
    ], {8 => "/api/items"}).should eq([guarded])
  end

  it "resolves a Vert.x handler variable to the declaration in scope, not another method's" do
    vertx_tags.call("MainVerticle.java", [
      "public class MainVerticle extends AbstractVerticle {",
      "  private Router adminRouter() {",
      "    Handler<RoutingContext> handler = BasicAuthHandler.create(provider);",
      "    admin.route(\"/admin/*\").handler(handler);",
      "    return admin;",
      "  }",
      "  public void start() {",
      "    Handler<RoutingContext> handler = ctx -> ctx.response().end(\"ok\");",
      "    router.get(\"/status\").handler(handler);",
      "  }",
      "}",
    ], {9 => "/status"}).should eq([[] of String])
  end

  it "reads a covering Vert.x registration written as a fluent chain or through a Route variable" do
    vertx_tags.call("MainVerticle.java", [
      "public class MainVerticle extends AbstractVerticle {",
      "  public void start() {",
      "    router",
      "        .route(\"/api/*\")",
      "        .handler(JWTAuthHandler.create(jwt));",
      "    Route admin = router.route(\"/admin/*\");",
      "    admin.handler(BasicAuthHandler.create(provider));",
      "    router.get(\"/api/items\").handler(ctx -> ctx.response().end(\"items\"));",
      "    router.get(\"/admin/users\").handler(ctx -> ctx.response().end(\"users\"));",
      "    router.get(\"/status\").handler(ctx -> ctx.response().end(\"ok\"));",
      "  }",
      "}",
    ], {8 => "/api/items", 9 => "/admin/users", 10 => "/status"}).should eq([guarded, guarded, [] of String])
  end

  it "does not count brackets inside Vert.x string literals" do
    vertx_tags.call("MainVerticle.java", [
      "public class MainVerticle extends AbstractVerticle {",
      "  public void start() {",
      "    router.route(\"/api/*\").handler(ctx -> { log.debug(\"api hit :(\"); ctx.next(); });",
      "    JWTAuthHandler adminAuth = JWTAuthHandler.create(jwt);",
      "    router.route(\"/admin/*\").handler(adminAuth);",
      "    router.get(\"/api/items\").handler(ctx -> ctx.response().end(\"items\"));",
      "    router.get(\"/me\").handler(routingContext -> {",
      "      log.debug(\"enter /me :) :)\");",
      "      if (routingContext.user() == null) {",
      "        routingContext.fail(401);",
      "        return;",
      "      }",
      "      routingContext.response().end(\"me\");",
      "    });",
      "  }",
      "}",
    ], {6 => "/api/items", 7 => "/me"}).should eq([[] of String, ["Protected by Vert.x user() check"]])
  end

  it "reads the body of a Vert.x handler passed as a method reference" do
    vertx_tags.call("MainVerticle.java", [
      "public class MainVerticle extends AbstractVerticle {",
      "  public void start() {",
      "    router.get(\"/me\").handler(this::secured);",
      "  }",
      "  private void secured(RoutingContext routingContext) {",
      "    if (routingContext.user() == null) {",
      "      routingContext.fail(401);",
      "      return;",
      "    }",
      "    routingContext.response().end(\"me\");",
      "  }",
      "}",
    ], {3 => "/me"}).should eq([["Protected by Vert.x user() check"]])
  end

  it "reads what the Vert.x handlers of every covering route require" do
    tmpdir = File.tempname("vertx_requires")
    Dir.mkdir_p(tmpdir)
    file = File.join(tmpdir, "ApiRoutes.java")
    File.write(file, [
      "public class ApiRoutes {",
      "  public void mount(Router router, JWTAuth jwt) {",
      "    router.route(\"/api/*\").handler(JWTAuthHandler.create(jwt));",
      "    router.route(\"/api/admin/*\").handler(AuthorizationHandler.create(RoleBasedAuthorization.create(\"admin\")));",
      "    router.get(\"/api/admin/users\").handler(ctx -> ctx.response().end(\"users\"));",
      "    router.get(\"/api/items\").handler(ctx -> ctx.response().end(\"items\"));",
      "    router.route(\"/raw/*\").handler(JWTAuth.create(vertx, config));",
      "    router.get(\"/raw/items\").handler(ctx -> ctx.response().end(\"raw\"));",
      "  }",
      "}",
    ].join("\n"))
    CodeLocator.instance.register_path(file)
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    endpoints = {5 => "/api/admin/users", 6 => "/api/items", 8 => "/raw/items"}.map do |line, url|
      details = Details.new(PathInfo.new(file, line))
      details.technology = "java_vertx"
      Endpoint.new(url, "GET", [] of Param, details)
    end
    JavaMiscAuthTagger.new(noir_options).perform(endpoints)
    FileUtils.rm_rf(tmpdir)

    endpoints.map { |endpoint| endpoint.tags.map(&.description) }.should eq([["Protected by Vert.x AuthHandler"], ["Protected by Vert.x AuthHandler"], ["Protected by Vert.x JWTAuth"]])
    endpoints.map { |endpoint| Access.of(endpoint).map(&.to_s) }.should eq([
      ["authenticated", "role:admin"],
      ["authenticated"],
      # `JWTAuth` builds a provider, which noir does not read as a handler.
      ["authenticated", "unresolved"],
    ])
  end
end
