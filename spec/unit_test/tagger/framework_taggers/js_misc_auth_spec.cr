require "../../../spec_helper"
require "../../../../src/tagger/tagger"
require "file_utils"

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

  describe "Fastify routes with TypeScript type arguments" do
    it "reads the preHandler of a typed route, and of the call its line names" do
      dir = File.tempname("fastify_typed")
      Dir.mkdir_p(dir)
      server = File.join(dir, "server.ts")
      File.write(server, <<-TS)
        import Fastify from 'fastify';
        const fastify = Fastify();
        async function requireUser(request, reply) {
          if (!request.user) return reply.code(401).send({ error: 'unauthorized' });
        }
        fastify.get<{ Querystring: { q: string } }>('/typed-guarded', { preHandler: requireUser }, async () => 1);
        fastify.get<{ Querystring: { q: string } }>('/typed-open', async () => 1);
        fastify.get<{ Q: Q }>('/a', async () => 1); fastify.get('/x2', { preHandler: requireUser }, async () => 1);
        fastify.get<{ Q: Q }>('/same', { preHandler: requireUser }, async () => 1); fastify.post('/same', async () => 1);
        TS
      begin
        noir_options = create_test_options
        noir_options["base"] = YAML::Any.new(dir)
        endpoints = {6 => "/typed-guarded", 7 => "/typed-open", 8 => "/a"}.map do |line, url|
          details = Details.new(PathInfo.new(server, line))
          details.technology = "js_fastify"
          Endpoint.new(url, "GET", [] of Param, details)
        end
        details = Details.new(PathInfo.new(server, 8))
        details.technology = "js_fastify"
        endpoints << Endpoint.new("/x2", "GET", [] of Param, details)
        %w[GET POST].each do |method|
          details = Details.new(PathInfo.new(server, 9))
          details.technology = "js_fastify"
          endpoints << Endpoint.new("/same", method, [] of Param, details)
        end
        tagged = JsMiscAuthTagger.new(noir_options).perform(endpoints)
        same = tagged.select { |ep| ep.url == "/same" }.to_h { |ep| {ep.method, ep.tags.map(&.description)} }
        same["GET"].should eq(["Protected by Fastify preHandler requireUser"])
        same["POST"].should be_empty
        tags = tagged.to_h { |ep| {ep.url, ep.tags.map(&.description)} }
        tags["/typed-guarded"].should eq(["Protected by Fastify preHandler requireUser"])
        tags["/typed-open"].should be_empty
        tags["/a"].should be_empty
        tags["/x2"].should eq(["Protected by Fastify preHandler requireUser"])
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end

  describe "Fastify route({ ... }) configs" do
    it "judges the config's onRequest hook by its definition" do
      dir = File.tempname("fastify_route_config")
      Dir.mkdir_p(File.join(dir, "plugins"))
      File.write(File.join(dir, "plugins", "verify-auth.ts"), <<-TS)
        export const verifyAuth =
          (modes: string[]) =>
          (req, _res, done) => {
            if (!req.auth) throw new UnauthorizedError({ message: "Token missing" });
            done();
          };
        export const checkOrigin = (req, _res, done) => {
          if (req.headers.origin !== "https://app") throw new ForbiddenRequestError({ message: "bad origin" });
          done();
        };
        export const logRequest = (req, _res, done) => { req.log.info("hit"); done(); };
        export const optionalAuth = (req, _res, done) => {
          if (req.headers.authorization) {
            if (!req.auth) throw new UnauthorizedError({ message: "bad token" });
          }
          done();
        };
        TS
      server = File.join(dir, "server.ts")
      File.write(server, <<-TS)
        import fastify from "fastify";
        import { checkOrigin, logRequest, optionalAuth, verifyAuth } from "./plugins/verify-auth";
        const server = fastify();
        server.route({ method: "GET", url: "/secrets", onRequest: verifyAuth(["jwt"]), handler: async () => [] });
        server.route({ method: ["POST", "PUT"], url: "/items", onRequest: (req, res, done) => { verifyAuth(["jwt"])(req, res, done); }, handler: async () => ({}) });
        server.route({ method: "GET", url: "/status", handler: async () => ({}) });
        server.route({ method: "POST", url: "/hook", onRequest: checkOrigin, handler: async () => ({}) });
        server.route({ method: "GET", url: "/logged", onRequest: logRequest, handler: async () => ({}) });
        server.route({ method: "GET", url: "/feed", onRequest: optionalAuth, handler: async () => [] });
        TS
      begin
        noir_options = create_test_options
        noir_options["base"] = YAML::Any.new(dir)
        endpoints = [{4, "GET", "/secrets"}, {5, "POST", "/items"}, {5, "PUT", "/items"},
                     {6, "GET", "/status"}, {7, "POST", "/hook"}, {8, "GET", "/logged"}, {9, "GET", "/feed"}].map do |line, method, url|
          details = Details.new(PathInfo.new(server, line))
          details.technology = "js_fastify"
          Endpoint.new(url, method, [] of Param, details)
        end
        tags = JsMiscAuthTagger.new(noir_options).perform(endpoints).to_h { |ep| {"#{ep.method} #{ep.url}", ep.tags.map(&.description)} }
        tags["GET /secrets"].should eq(["Protected by Fastify onRequest verifyAuth"])
        tags["POST /items"].should eq(["Protected by Fastify onRequest verifyAuth"])
        tags["PUT /items"].should eq(["Protected by Fastify onRequest verifyAuth"])
        tags["GET /status"].should be_empty
        # A 403 for a bad origin is a CSRF check, not a credential check.
        tags["POST /hook"].should be_empty
        tags["GET /logged"].should be_empty
        # Refuses a bad token only when one is sent: anonymous callers pass.
        tags["GET /feed"].should be_empty
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end

  it "returns correct target_techs" do
    JsMiscAuthTagger.target_techs.should contain("js_fastify")
    JsMiscAuthTagger.target_techs.should contain("js_koa")
    JsMiscAuthTagger.target_techs.should contain("js_restify")
  end

  it "reads Fastify route calls in linear time when a string holds a route-call look-alike" do
    timed = ->(n : Int32) do
      dir = File.tempname("fastify_linear")
      Dir.mkdir_p(dir)
      path = File.join(dir, "app.js")
      File.write(path, String.build { |io| n.times { |k| io << "fastify.get('/r#{k}', async () => 'ok'); log('.get(')\n" } })
      options = create_test_options
      options["base"] = YAML::Any.new(dir)
      endpoints = (1..n).map do |k|
        details = Details.new(PathInfo.new(path, k))
        details.technology = "js_fastify"
        Endpoint.new("/r#{k - 1}", "GET", [] of Param, details)
      end
      started = Time.instant
      JsMiscAuthTagger.new(options).perform(endpoints)
      elapsed = (Time.instant - started).total_seconds
      FileUtils.rm_rf(dir)
      elapsed
    end
    small = timed.call(500)
    large = timed.call(2000)
    # Linear is ~4x; growing every read to the end of the file was ~16x.
    (large < small * 10 || large < 0.3).should be_true
  end
end
