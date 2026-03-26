require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "JavaMiscAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/java/vertx_auth"
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
      locator.push("file_map", file)
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
      locator.push("file_map", file)
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
      locator.push("file_map", file)
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
      locator.push("file_map", file)
    end

    # Line 8: router.get("/public/health").handler(ctx -> {
    details = Details.new(PathInfo.new(health_path, 8))
    details.technology = "java_vertx"
    endpoint = Endpoint.new("/public/health", "GET", [] of Param, details)

    tagger = JavaMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
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
