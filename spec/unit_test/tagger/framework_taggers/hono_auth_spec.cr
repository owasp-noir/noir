require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "HonoAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/javascript/hono_auth"
  app_path = "#{fixture_base}/app.ts"

  # app.ts line reference (see actual fixture):
  #  12: app.get('/api/secure', bearerAuth(...), ...)
  #  17: app.use('/admin/*', jwt(...))
  #  19: app.get('/admin/dashboard'...
  #  25: app.use('/basic/*', basicAuth(...))
  #  37: app.use('/protected/*', authMiddleware)
  #  39: app.get('/protected/profile'...
  #  45: app.get('/me', authMiddleware, ...)
  #  50: app.get('/health'...

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects bearerAuth middleware on route" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 12))
    details.technology = "js_hono"
    endpoint = Endpoint.new("/api/secure", "GET", [] of Param, details)

    tagger = HonoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("hono_auth")
    endpoint.tags[0].description.should contain("bearerAuth")
  end

  it "detects jwt middleware via app.use prefix scope" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 19))
    details.technology = "js_hono"
    endpoint = Endpoint.new("/admin/dashboard", "GET", [] of Param, details)

    tagger = HonoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("jwt")
  end

  it "detects custom authMiddleware chained on route" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 45))
    details.technology = "js_hono"
    endpoint = Endpoint.new("/me", "GET", [] of Param, details)

    tagger = HonoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("authMiddleware")
  end

  it "does not tag public health endpoint" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 50))
    details.technology = "js_hono"
    endpoint = Endpoint.new("/health", "GET", [] of Param, details)

    tagger = HonoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end
end
