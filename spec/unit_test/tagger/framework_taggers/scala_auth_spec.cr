require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "ScalaAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/scala/akka_auth"
  routes_path = "#{fixture_base}/Routes.scala"
  health_path = "#{fixture_base}/HealthRoutes.scala"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects Akka HTTP authenticateBasic" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    # Routes.scala line 10: get { complete("Secure content") }
    details = Details.new(PathInfo.new(routes_path, 10))
    details.technology = "scala_akka"
    endpoint = Endpoint.new("/api/secure", "GET", [] of Param, details)

    tagger = ScalaAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("scala_auth")
    endpoint.tags[0].description.should contain("authenticateBasic")
  end

  it "detects Akka HTTP authenticateOAuth2" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    # Routes.scala line 21: get { complete("OAuth resource") }
    details = Details.new(PathInfo.new(routes_path, 21))
    details.technology = "scala_akka"
    endpoint = Endpoint.new("/api/oauth-resource", "GET", [] of Param, details)

    tagger = ScalaAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("authenticateOAuth2")
  end

  it "detects Akka HTTP authorize directive" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    # Routes.scala line 32: get { complete("Admin settings") }
    details = Details.new(PathInfo.new(routes_path, 32))
    details.technology = "scala_akka"
    endpoint = Endpoint.new("/api/admin/settings", "GET", [] of Param, details)

    tagger = ScalaAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("authorize")
  end

  it "does not tag unprotected routes" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    # HealthRoutes.scala line 11: get { complete("ok") }
    details = Details.new(PathInfo.new(health_path, 11))
    details.technology = "scala_akka"
    endpoint = Endpoint.new("/public/health", "GET", [] of Param, details)

    tagger = ScalaAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "handles empty code_paths gracefully" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new
    details.technology = "scala_akka"
    endpoint = Endpoint.new("/unknown/", "GET", [] of Param, details)

    tagger = ScalaAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "returns correct target_techs" do
    ScalaAuthTagger.target_techs.should contain("scala_play")
    ScalaAuthTagger.target_techs.should contain("scala_akka")
    ScalaAuthTagger.target_techs.should contain("scala_scalatra")
    ScalaAuthTagger.target_techs.should contain("java_play")
  end
end
