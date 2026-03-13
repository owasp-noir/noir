require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "KtorAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/kotlin/ktor_auth"
  app_path = "#{fixture_base}/src/Application.kt"

  # Application.kt line reference:
  # 10:     get("/public") {
  # 14:     authenticate("auth-jwt") {
  # 15:       get("/profile") {
  # 20:       post("/api/data") {
  # 25:     authenticate("auth-session") {
  # 26:       route("/admin") {
  # 27:         get("/dashboard") {
  # 33:     get("/health") {

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects authenticate block wrapping route" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 15))
    details.technology = "kotlin_ktor"
    endpoint = Endpoint.new("/profile", "GET", [] of Param, details)

    tagger = KtorAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("ktor_auth")
    endpoint.tags[0].description.should contain("authenticate")
  end

  it "detects principal access in handler" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 15))
    details.technology = "kotlin_ktor"
    endpoint = Endpoint.new("/profile", "GET", [] of Param, details)

    tagger = KtorAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
  end

  it "does not tag public routes" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 10))
    details.technology = "kotlin_ktor"
    endpoint = Endpoint.new("/public", "GET", [] of Param, details)

    tagger = KtorAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "does not tag health route outside authenticate block" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 33))
    details.technology = "kotlin_ktor"
    endpoint = Endpoint.new("/health", "GET", [] of Param, details)

    tagger = KtorAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "detects authenticate block with nested route() block" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 27))
    details.technology = "kotlin_ktor"
    endpoint = Endpoint.new("/admin/dashboard", "GET", [] of Param, details)

    tagger = KtorAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("ktor_auth")
    endpoint.tags[0].description.should contain("auth-session")
  end
end
