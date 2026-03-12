require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "GoAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/go/gin_auth"
  main_path = "#{fixture_base}/main.go"

  # main.go line reference:
  # 14: r.GET("/health", func(c *gin.Context) {
  # 18: r.GET("/public", func(c *gin.Context) {
  # 23: api := r.Group("/api")
  # 24: api.Use(AuthMiddleware())
  # 25: api.GET("/profile", func(c *gin.Context) {
  # 30: r.GET("/dashboard", AuthRequired, func(c *gin.Context) {
  # 35: r.DELETE("/admin/users/:id", AdminOnly, func(c *gin.Context) {

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects inline auth middleware (AuthRequired)" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(main_path, 30))
    details.technology = "go_gin"
    endpoint = Endpoint.new("/dashboard", "GET", [] of Param, details)

    tagger = GoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("go_auth")
    endpoint.tags[0].description.should contain("AuthRequired")
  end

  it "detects inline AdminOnly middleware" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(main_path, 35))
    details.technology = "go_gin"
    endpoint = Endpoint.new("/admin/users/1", "DELETE", [] of Param, details)

    tagger = GoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("AdminOnly")
  end

  it "detects group-level Use(AuthMiddleware)" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(main_path, 25))
    details.technology = "go_gin"
    endpoint = Endpoint.new("/api/profile", "GET", [] of Param, details)

    tagger = GoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("AuthMiddleware")
  end

  it "does not tag public endpoints" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(main_path, 14))
    details.technology = "go_gin"
    endpoint = Endpoint.new("/health", "GET", [] of Param, details)

    tagger = GoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "handles empty code_paths gracefully" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new
    details.technology = "go_gin"
    endpoint = Endpoint.new("/unknown/", "GET", [] of Param, details)

    tagger = GoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end
end
