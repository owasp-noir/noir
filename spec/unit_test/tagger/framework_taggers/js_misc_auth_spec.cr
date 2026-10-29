require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "JsMiscAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/javascript/fastify_auth", __DIR__)
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
      locator.register_path(file)
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
      locator.register_path(file)
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
      locator.register_path(file)
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
      locator.register_path(file)
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
      locator.register_path(file)
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

  describe "Koa middleware read at its definition" do
    koa_base = File.expand_path("../../../functional_test/fixtures/javascript/koa_mount_rpc", __DIR__)
    documents = "#{koa_base}/server/api/documents/documents.ts"

    # documents.ts: line 7 `auth({ optional: true })`, 16 `auth()`, 26 no
    # middleware. `auth` is imported through a tsconfig `paths` alias; its
    # refusal (`throw AuthenticationError`) sits in a helper whose signature
    # wraps over a `Promise<{ … }>` return type.
    tags_at = ->(line : Int32) do
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(koa_base)
      details = Details.new(PathInfo.new(documents, line))
      details.technology = "js_koa"
      endpoint = Endpoint.new("/api/x", "POST", [] of Param, details)
      JsMiscAuthTagger.new(noir_options).perform([endpoint])
      endpoint.tags
    end

    it "counts a middleware whose definition refuses the caller as a guard" do
      tags = tags_at.call(16)
      tags.size.should eq(1)
      tags[0].description.should eq("Protected by Koa auth middleware (throw AuthenticationError)")
    end

    it "does not count it when an option the definition branches on lets the caller through" do
      tags_at.call(7).should be_empty
    end

    it "reports nothing for a route without middleware" do
      tags_at.call(26).should be_empty
    end
  end

  # koa_router_use_guard/src/app.ts: `admin.use(requireLogin)` before
  # `admin.get('/items')`; `scoped.use('/private', requireLogin)` between
  # `/before` and the `/private` and `/public` routes; a route that only
  # reads `ctx.state.user` and one that refuses without it (#3263).
  # index.ts: `auth()` in front of a short handler and of one over 80
  # lines (#3308).
  describe "Koa router.use and long route calls" do
    koa_base = File.expand_path("../../../functional_test/fixtures/javascript/koa_router_use_guard", __DIR__)
    verdicts = ->(file : String, lines : Hash(Int32, String)) do
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(koa_base)
      endpoints = lines.map do |line, url|
        details = Details.new(PathInfo.new("#{koa_base}/src/#{file}", line))
        details.technology = "js_koa"
        Endpoint.new(url, "GET", [] of Param, details)
      end
      JsMiscAuthTagger.new(noir_options).perform(endpoints).to_h { |ep| {ep.url, ep.tags.map(&.description)} }
    end

    it "applies router.use middleware to that router's later routes, scoped by its path" do
      tags = verdicts.call("app.ts", {12 => "/admin/items", 13 => "/me", 14 => "/whoami", 15 => "/mine", 21 => "/before", 23 => "/private/report", 24 => "/public/report",
                                      34 => "/health", 36 => "/status", 43 => "/ops/run", 44 => "/docs"})
      tags["/admin/items"].should eq(["Protected by Koa requireLogin middleware (ctx.throw(401))"])
      tags["/me"].should eq(["Protected by Koa requireLogin middleware (ctx.throw(401))"])
      tags["/whoami"].should be_empty
      tags["/mine"].should eq(["Protected by Koa ctx.state.user check"])
      tags["/before"].should be_empty
      tags["/private/report"].should eq(["Protected by Koa requireLogin middleware (ctx.throw(401))"])
      tags["/public/report"].should be_empty
      # A same-named router in another function, a commented-out use and a
      # use after the route guard nothing; a list of paths scopes the use.
      tags["/health"].should be_empty
      tags["/status"].should be_empty
      tags["/ops/run"].should eq(["Protected by Koa requireLogin middleware (ctx.throw(401))"])
      tags["/docs"].should be_empty
    end

    it "reads a route's middleware however long its handler runs" do
      tags = verdicts.call("index.ts", {14 => "/items.short", 17 => "/items.long"})
      tags["/items.short"].should eq(["Protected by Koa auth middleware (throw AuthenticationError)"])
      tags["/items.long"].should eq(["Protected by Koa auth middleware (throw AuthenticationError)"])
    end
  end

  it "returns correct target_techs" do
    JsMiscAuthTagger.target_techs.should contain("js_fastify")
    JsMiscAuthTagger.target_techs.should contain("js_koa")
    JsMiscAuthTagger.target_techs.should contain("js_restify")
  end
end
