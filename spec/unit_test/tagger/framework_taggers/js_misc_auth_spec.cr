require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "JsMiscAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/javascript/fastify_auth"
  app_path = "#{fixture_base}/app.js"

  # app.js line reference:
  #  4: fastify.get('/api/secure', { preHandler: authenticate }, ...)
  #  9: fastify.post('/api/data', { onRequest: authenticate }, ...)
  # 14: fastify.get('/profile', { preHandler: [fastify.authenticate] }, ...)
  # 19: fastify.get('/dashboard', { preHandler: verifyToken }, ...)
  # 33: fastify.get('/public/health', ...) (no auth, far from auth patterns)

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects Fastify preHandler authenticate" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 4))
    details.technology = "js_fastify"
    endpoint = Endpoint.new("/api/secure", "GET", [] of Param, details)

    tagger = JsMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("js_misc_auth")
    endpoint.tags[0].description.should contain("authenticate")
  end

  it "detects Fastify onRequest authenticate" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 9))
    details.technology = "js_fastify"
    endpoint = Endpoint.new("/api/data", "POST", [] of Param, details)

    tagger = JsMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("authenticate")
  end

  it "detects fastify.authenticate decorator" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 14))
    details.technology = "js_fastify"
    endpoint = Endpoint.new("/profile", "GET", [] of Param, details)

    tagger = JsMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("authenticate")
  end

  it "detects generic verifyToken middleware" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 19))
    details.technology = "js_fastify"
    endpoint = Endpoint.new("/dashboard", "GET", [] of Param, details)

    tagger = JsMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("verifyToken")
  end

  it "does not tag unprotected routes" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 33))
    details.technology = "js_fastify"
    endpoint = Endpoint.new("/public/health", "GET", [] of Param, details)

    tagger = JsMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "handles empty code_paths gracefully" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new
    details.technology = "js_fastify"
    endpoint = Endpoint.new("/unknown/", "GET", [] of Param, details)

    tagger = JsMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "returns correct target_techs" do
    JsMiscAuthTagger.target_techs.should contain("js_fastify")
    JsMiscAuthTagger.target_techs.should contain("js_koa")
    JsMiscAuthTagger.target_techs.should contain("js_restify")
  end
end
