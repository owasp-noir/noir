require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "HonoAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/javascript/hono_auth", __DIR__)
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
      locator.register_path(file)
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
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(app_path, 19))
    details.technology = "js_hono"
    endpoint = Endpoint.new("/admin/dashboard", "GET", [] of Param, details)

    tagger = HonoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("app.use() auth on /admin/")
  end

  it "detects custom authMiddleware chained on route" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
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
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(app_path, 50))
    details.technology = "js_hono"
    endpoint = Endpoint.new("/health", "GET", [] of Param, details)

    tagger = HonoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "bounds the middleware and context-user windows by statement" do
    tmpdir = File.tempname("hono_statement")
    Dir.mkdir_p(tmpdir)
    index_ts = File.join(tmpdir, "index.ts")
    File.write(index_ts, [
      "const app = new Hono()",
      "app.get('/me', requireAuth, (c) => c.json({ ok: true }))",
      "app.get('/public', (c) => c.text('hi'))",
      "app.get('/health', (c) => c.text('ok'))",
      "app.get('/whoami', (c) => {",
      "  return c.json(c.var.user)",
      "})",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    CodeLocator.instance.register_path(index_ts)

    me = Endpoint.new("/me", "GET", [] of Param, Details.new(PathInfo.new(index_ts, 2)))
    pub = Endpoint.new("/public", "GET", [] of Param, Details.new(PathInfo.new(index_ts, 3)))
    health = Endpoint.new("/health", "GET", [] of Param, Details.new(PathInfo.new(index_ts, 4)))
    whoami = Endpoint.new("/whoami", "GET", [] of Param, Details.new(PathInfo.new(index_ts, 5)))

    HonoAuthTagger.new(noir_options).perform([me, pub, health, whoami])

    me.tags.map(&.description).should eq(["Protected by Hono requireAuth middleware"])
    pub.tags.should be_empty
    health.tags.should be_empty
    whoami.tags.map(&.description).should eq(["Protected by Hono auth (context user extraction)"])

    FileUtils.rm_rf(tmpdir)
  end
end
