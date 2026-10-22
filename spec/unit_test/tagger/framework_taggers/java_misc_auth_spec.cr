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
end
