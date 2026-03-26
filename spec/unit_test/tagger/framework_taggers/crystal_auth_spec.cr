require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "CrystalAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/crystal/kemal_auth"
  app_path = "#{fixture_base}/app.cr"

  # app.cr line reference:
  #  4: get "/profile" do |env|
  #  5:   user = env.session.string("user_id")
  # 10: get "/api/secret" do |env|
  # 11:   basic_auth env
  # 18:   get "/api/health" do |env|  (unprotected, in separate class)

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects Kemal session user check" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 4))
    details.technology = "crystal_kemal"
    endpoint = Endpoint.new("/profile", "GET", [] of Param, details)

    tagger = CrystalAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("crystal_auth")
  end

  it "detects Kemal basic_auth" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 10))
    details.technology = "crystal_kemal"
    endpoint = Endpoint.new("/api/secret", "GET", [] of Param, details)

    tagger = CrystalAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("basic_auth")
  end

  it "does not tag unprotected routes" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 18))
    details.technology = "crystal_kemal"
    endpoint = Endpoint.new("/api/health", "GET", [] of Param, details)

    tagger = CrystalAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "handles empty code_paths gracefully" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new
    details.technology = "crystal_kemal"
    endpoint = Endpoint.new("/unknown/", "GET", [] of Param, details)

    tagger = CrystalAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "returns correct target_techs" do
    CrystalAuthTagger.target_techs.should contain("crystal_kemal")
    CrystalAuthTagger.target_techs.should contain("crystal_amber")
    CrystalAuthTagger.target_techs.should contain("crystal_lucky")
  end
end
