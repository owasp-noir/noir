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

    it "follows a router passed to another module's route function back to the callers' use" do
      CodeLocator.instance.clear_all
      dir = File.tempname("koa_router_param")
      Dir.mkdir_p(File.join(dir, "routes", "account"))
      files = {
        "middleware/auth.ts" => <<-TS,
          export default function koaAuth(audience: string) {
            return async (ctx, next) => {
              const { scopes } = await verify(ctx.request, audience);
              assertThat(scopes.includes('all'), new RequestError({ code: 'auth.forbidden', status: 403 }));
              return next();
            };
          }
          TS
        "routes/init.ts" => <<-TS,
          import koaAuth from '../middleware/auth.js';
          import itemRoutes from './items.js';
          import accountRoutes from './account/index.js';
          import publicRoutes from './public.js';
          import sharedRoutes from './shared.js';
          import listedRoutes from './listed.js';
          import typedRoutes from './typed.js';

          export default function init(tenant) {
            const managementRouter: ManagementApiRouter = new Router();
            managementRouter.use(koaAuth(tenant.audience));
            itemRoutes(managementRouter, tenant);
            accountRoutes(managementRouter, tenant);
            sharedRoutes(managementRouter, tenant);
            listedRoutes(managementRouter);
            typedRoutes(tenant, managementRouter);

            const anonymousRouter = new Router();
            publicRoutes(anonymousRouter, tenant);
            sharedRoutes(anonymousRouter, tenant);
            [listedRoutes].forEach((register) => register(anonymousRouter));
          }
          TS
        "routes/items.ts" => <<-TS,
          export default function itemRoutes<T extends ManagementApiRouter>(
            ...[router, { queries }]: RouterInitArgs<T>
          ) {
            router.get('/items', async (ctx, next) => next());
          }
          TS
        "routes/account/index.ts" => <<-TS,
          import emailRoutes from './email.js';

          export default function accountRoutes(...args: RouterInitArgs<T>) {
            emailRoutes(...args);
          }
          TS
        "routes/account/email.ts" => <<-TS,
          export default function emailRoutes(router, tenant) {
            router.post('/account/email', async (ctx, next) => next());
          }
          TS
        "routes/public.ts" => <<-TS,
          export default function publicRoutes(router, tenant) {
            router.get('/status', async (ctx, next) => next());
          }
          TS
        "routes/shared.ts" => <<-TS,
          export default function sharedRoutes(router, tenant) {
            router.get('/shared', async (ctx, next) => next());
          }
          TS
        "routes/mixed.ts" => <<-TS,
          import koaAuth from '../middleware/auth.js';

          function adminRoutes(router) {
            router.use(koaAuth('admin'));
            router.get('/admin', async (ctx, next) => next());
          }

          export default function mixedRoutes(router, tenant) {
            router.get('/mixed', async (ctx, next) => next());
          }

          router.get('/module-level', async (ctx, next) => next());
          TS
        "routes/legacy.js" => <<-JS,
          const mixedRoutes = require('./mixed');
          const legacyRouter = new Router();
          mixedRoutes(legacyRouter);
          JS
        "routes/late.ts" => <<-TS,
          export default function lateRoutes(tenant, router) {
            router.get('/late', async (ctx, next) => next());
          }
          TS
        "routes/late-callers.ts" => <<-TS,
          import koaAuth from '../middleware/auth.js';
          import lateRoutes from './late.js';

          export function guarded(tenant, ...args) {
            const authed = new Router();
            authed.use(koaAuth('x'));
            lateRoutes(tenant, authed);
            lateRoutes(...args);
          }
          TS
        "routes/local.ts" => <<-TS,
          import koaAuth from '../middleware/auth.js';
          const router = new Router();
          router.use(koaAuth('x'));
          function register(router) {
            router.get('/local', async (ctx, next) => next());
          }
          register(router);
          TS
        "routes/listed.ts" => <<-TS,
          export default function listedRoutes(router) {
            router.get('/listed', async (ctx, next) => next());
          }
          TS
        "routes/typed.ts" => <<-TS,
          export default function typedRoutes(tenant: Ctx<A, B>, router: Router) {
            router.get('/typed', async (ctx, next) => next());
          }
          TS
        "middleware/errors.ts" => <<-TS,
          export default function koaErrors() {
            return async (ctx, next) => {
              try {
                await next();
              } catch (error) {
                throw new RequestError({ code: 'auth.unauthorized', data: { error }, status: 401 });
              }
            };
          }
          TS
        "routes/errors.ts" => <<-TS,
          import koaErrors from '../middleware/errors.js';
          const router = new Router();
          router.use(koaErrors());
          router.get('/errors', async (ctx, next) => next());
          TS
        "middleware/public-paths.ts" => <<-TS,
          export default function publicPaths() {
            return async (ctx, next) => {
              if (ctx.path === '/health') return next();
              if (!ctx.state.user) throw new RequestError({ code: 'auth.unauthorized', status: 401 });
              await next();
            };
          }
          TS
        "routes/paths.ts" => <<-TS,
          import publicPaths from '../middleware/public-paths.js';
          const router = new Router();
          router.use(publicPaths());
          router.get('/paths', async (ctx, next) => next());
          TS
        "routes/twice.ts" => <<-TS,
          export default function twiceRoutes(router) {
            router.get('/twice', async (ctx, next) => next());
          }
          TS
        "routes/twice-caller.ts" => <<-TS,
          import koaAuth from '../middleware/auth.js';
          import twiceRoutes from './twice.js';
          const authed = new Router();
          authed.use(koaAuth('x'));
          const open = new Router();
          twiceRoutes(authed); twiceRoutes(open);
          TS
        "routes/barrel-target.ts" => <<-TS,
          export default function barrelRoutes(router) {
            router.get('/barrel', async (ctx, next) => next());
          }
          TS
        "routes/barrel.ts" => <<-TS,
          import koaAuth from '../middleware/auth.js';
          import barrelRoutes from './barrel-target.js';
          export * as everything from './barrel-target.js';
          const authed = new Router();
          authed.use(koaAuth('x'));
          barrelRoutes(authed);
          TS
        "middleware/verify.ts" => <<-TS,
          export default function verifyJwt() {
            return async (ctx, next) => {
              try { await cache.warm(ctx) } catch {}
              try {
                ctx.state.user = jwt.verify(ctx.headers.authorization);
              } catch (error) {
                throw new RequestError({ code: 'auth.unauthorized', status: 401 });
              }
              await next();
            };
          }
          TS
        "routes/verified.ts" => <<-TS,
          import verifyJwt from '../middleware/verify.js';
          const router = new Router();
          router.use(verifyJwt());
          router.get('/verified', async (ctx, next) => next());
          TS
        "routes/named.ts" => <<-TS,
          export function namedRoutes(...[router, tenant]: [Router, Tenant]) {
            router.get('/named', async (ctx, next) => next());
          }
          TS
        "routes/named-caller.ts" => <<-TS,
          import koaAuth from '../middleware/auth.js';
          import {
            namedRoutes,
          } from './named.js';
          const authed = new Router();
          authed.use(koaAuth('x'));
          namedRoutes(authed, tenant);
          TS
        "routes/spaced.ts" => <<-TS,
          export function spacedRoutes(router) {
            router.get('/spaced', async (ctx, next) => next());
          }
          TS
        "routes/spaced-callers.ts" => <<-TS,
          import koaAuth from '../middleware/auth.js';
          import { spacedRoutes } from './spaced.js';
          import * as all from './spaced.js';
          const authed = new Router();
          authed.use(koaAuth('x'));
          spacedRoutes(authed);
          all.spacedRoutes(new Router());
          TS
        "routes/items.test.ts" => <<-TS,
          const itemRoutes = await pickDefault(import('./items.js'));
          const request = createRequester({ authedRoutes: itemRoutes });
          TS
        "routes/lazy.ts" => <<-TS,
          export default function lazyRoutes(router) {
            router.get('/lazy', async (ctx, next) => next());
          }
          TS
        "routes/lazy-callers.ts" => <<-TS,
          import koaAuth from '../middleware/auth.js';
          import lazyRoutes from './lazy.js';
          const authed = new Router();
          authed.use(koaAuth('x'));
          lazyRoutes(authed);
          import('./lazy.js').then((m) => m.default(new Router()));
          TS
        "middleware/preflight.ts" => <<-TS,
          export default function preflight() {
            return async (ctx, next) => {
              if (ctx.method === 'OPTIONS') return next();
              try {
                ctx.state.user = verify(ctx.headers.authorization);
              } catch (error) {
                ctx.throw(401);
              }
              await next();
            };
          }
          TS
        "routes/preflight.ts" => <<-TS,
          import preflight from '../middleware/preflight.js';
          const router = new Router();
          router.use(preflight());
          router.get('/preflight', async (ctx, next) => next());
          TS
        "middleware/loose.ts" => <<-TS,
          export default function loose() {
            return async (ctx, next) => {
              assert(ctx.query.input, 'bad')
              ctx.body = serialize(ctx, new HttpError({ status: 401 }))
              return next()
            }
          }
          TS
        "routes/loose.ts" => <<-TS,
          import loose from '../middleware/loose.js';
          const router = new Router();
          router.use(loose());
          router.get('/loose', async (ctx, next) => next());
          TS
      }
      files.each do |name, body|
        file = File.join(dir, name)
        Dir.mkdir_p(File.dirname(file))
        File.write(file, body)
        CodeLocator.instance.register_path(file)
      end

      begin
        noir_options = create_test_options
        noir_options["base"] = YAML::Any.new(dir)
        endpoints = {"routes/items.ts" => {4, "/items"}, "routes/account/email.ts" => {2, "/account/email"},
                     "routes/public.ts" => {2, "/status"}, "routes/shared.ts" => {2, "/shared"},
                     "routes/mixed.ts" => {9, "/mixed"}, "routes/late.ts" => {2, "/late"},
                     "routes/loose.ts" => {4, "/loose"}, "routes/local.ts" => {5, "/local"},
                     "routes/listed.ts" => {2, "/listed"}, "routes/typed.ts" => {2, "/typed"},
                     "routes/errors.ts" => {4, "/errors"}, "routes/paths.ts" => {4, "/paths"},
                     "routes/twice.ts" => {2, "/twice"}, "routes/barrel-target.ts" => {2, "/barrel"},
                     "routes/verified.ts" => {4, "/verified"}, "routes/named.ts" => {2, "/named"},
                     "routes/spaced.ts" => {2, "/spaced"}, "routes/lazy.ts" => {2, "/lazy"},
                     "routes/preflight.ts" => {4, "/preflight"}}.map do |file, (line, url)|
          details = Details.new(PathInfo.new(File.join(dir, file), line))
          details.technology = "js_koa"
          Endpoint.new(url, "GET", [] of Param, details)
        end
        tags = JsMiscAuthTagger.new(noir_options).perform(endpoints).to_h { |ep| {ep.url, ep.tags.map(&.description)} }
        guard = "Protected by Koa koaAuth middleware (assertThat(scopes.includes('all'), new RequestError({ code: 'auth.forbidden', status: 403})))"
        # The test harness mounting it by reference is no caller.
        tags["/items"].should eq([guard])
        # Through `accountRoutes(...args)` to its caller.
        tags["/account/email"].should eq([guard])
        tags["/status"].should be_empty
        # One caller passes an unguarded router.
        tags["/shared"].should be_empty
        # Not the `router.use` of an earlier function, and its only caller
        # (a `require`) passes an unguarded router.
        tags["/mixed"].should be_empty
        # A caller passing too few arguments to read leaves the verdict open.
        tags["/late"].should be_empty
        # An assertion ends at its closing paren, semicolons or not.
        tags["/loose"].should be_empty
        # A module-level router handed to a function of the same file.
        tags["/local"].should eq([guard])
        # Also passed by reference, where the router it gets is not read.
        tags["/listed"].should be_empty
        # A type argument's comma is no parameter of its own.
        tags["/typed"].should eq([guard])
        # A 401 rethrown after `next()` refuses nobody; one after a public
        # path's early return still refuses the rest.
        tags["/errors"].should be_empty
        tags["/paths"].should eq(["Protected by Koa publicPaths middleware (throw new RequestError({ code: 'auth.unauthorized', status: 401}))"])
        # Two calls on a line, or a re-export, leave the callers unread.
        tags["/twice"].should be_empty
        tags["/barrel"].should be_empty
        # A refusal in the catch around a token check, past a closed catch.
        tags["/verified"].should eq(["Protected by Koa verifyJwt middleware (throw new RequestError({ code: 'auth.unauthorized', status: 401}))"])
        # A wrapped named import, and a typed rest pattern.
        tags["/named"].should eq([guard])
        # A namespace import reaches the function unread.
        tags["/spaced"].should be_empty
        # A dynamic import outside the tests is a caller left unread.
        tags["/lazy"].should be_empty
        # An early `return next()` is not the `try` the catch belongs to.
        tags["/preflight"].should eq(["Protected by Koa preflight middleware (ctx.throw(401))"])
      ensure
        FileUtils.rm_rf(dir)
        CodeLocator.instance.clear_all
      end
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

  describe "Fastify hooks that refuse by throwing" do
    # Writes `files` under a temp dir, tags every route the server file
    # declares (`url: "/x"` or `.get("/x"`), and returns url => auth tags.
    tag_routes = ->(files : Hash(String, String), server : String) do
      dir = File.tempname("fastify_throw")
      begin
        files.each do |name, text|
          path = File.join(dir, name)
          Dir.mkdir_p(File.dirname(path))
          File.write(path, text)
          CodeLocator.instance.register_path(path)
        end
        noir_options = create_test_options
        noir_options["base"] = YAML::Any.new(dir)
        server_path = File.join(dir, server)
        endpoints = [] of Endpoint
        File.read_lines(server_path).each_with_index do |line, idx|
          url = line.match(/url:\s*"([^"]+)"/).try(&.[1]) || line.match(/\.get\(\s*"([^"]+)"/).try(&.[1]) || next
          details = Details.new(PathInfo.new(server_path, idx + 1))
          details.technology = "js_fastify"
          verb = line.match(/method:\s*"([A-Z]+)"/).try(&.[1]) || "GET"
          endpoints << Endpoint.new(url, verb, [] of Param, details)
        end
        JsMiscAuthTagger.new(noir_options).perform(endpoints).to_h { |ep| {ep.url, ep.tags.select(&.name.==("auth")).map(&.description)} }
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "credits only a top-level absence test with no way out before it" do
      tags = tag_routes.call({
        "src/hooks.ts" => <<-JS,
          import { UnauthorizedError } from "./errors";

          // A: anonymous callers return early; only a bad token is refused.
          export const earlyReturn = (req, _res, done) => {
            const token = req.headers.authorization;
            if (!token) return done();
            if (!isValid(token)) throw new UnauthorizedError("bad token");
            done();
          };

          // B: presence test without braces.
          export const braceless = (req, _res, done) => {
            if (req.headers.authorization && !isValid(req.headers.authorization)) throw new UnauthorizedError("bad token");
            done();
          };

          // C: presence block with a nested block around the throw.
          export const nestedOptional = (req, _res, done) => {
            if (req.headers.authorization) {
              const user = decode(req.headers.authorization);
              if (!user) {
                throw new UnauthorizedError("bad token");
              }
              req.user = user;
            }
            done();
          };

          // D: bracketed header name (string is blanked by code_only).
          export const bracketHeader = (req, _res, done) => {
            if (req.headers["authorization"]) {
              if (!isValid(req.headers["authorization"])) throw new UnauthorizedError("bad token");
            }
            done();
          };

          // E: x-api-key presence block.
          export const apiKeyOptional = (req, _res, done) => {
            if (req.headers.apikey) {
              throw new UnauthorizedError("bad key");
            }
            done();
          };

          // F: else branch of an absence test.
          export const elseBranch = (req, _res, done) => {
            if (!req.headers.authorization) {
              done();
            } else {
              throw new UnauthorizedError("bad token");
            }
          };

          // G: guest-only hook: refuses when a session IS present.
          export const guestOnly = (req, _res, done) => {
            if (req.session.user) throw new UnauthorizedError("already signed in");
            done();
          };

          // H: option that opens the route.
          export const verifyAuthOpt =
            (opts: { optional?: boolean }) =>
            (req, _res, done) => {
              if (opts.optional && !req.auth) return done();
              if (!req.auth) throw new UnauthorizedError("Token missing");
              done();
            };

          // I: one mode allows anonymous callers.
          export const verifyModes =
            (modes: string[]) =>
            (req, _res, done) => {
              if (modes.includes("anonymous")) return done();
              if (!req.auth) throw new UnauthorizedError("Token missing");
              done();
            };

          // J: rate limiter / logger
          export const rateLimiter = (req, reply, done) => {
            if (tooMany(req.ip)) return reply.code(429).send();
            done();
          };
          export const logOnly = (req, _res, done) => {
            req.log.info("hit");
            done();
          };

          // K: real guard
          export const requireAuth =
            (modes: string[]) =>
            (req, _res, done) => {
              if (!req.auth) throw new UnauthorizedError("Token missing");
              done();
            };

          // L: throw in a catch after an early return for no token.
          export const catchOnly = async (req) => {
            if (!req.headers.authorization) return;
            try {
              await verify(req.headers.authorization);
            } catch (e) {
              throw new UnauthorizedError("bad token");
            }
          };

          // M: fastify-auth strategies
          export const strictStrategy = (req, _res, done) => {
            if (!req.user) throw new UnauthorizedError("no user");
            done();
          };
          export const publicStrategy = (req, _res, done) => done();
          JS
        "src/server.ts" => <<-JS,
          import fastify from "fastify";
          import { earlyReturn, braceless, nestedOptional, bracketHeader, apiKeyOptional, elseBranch, guestOnly, verifyAuthOpt, verifyModes, rateLimiter, logOnly, requireAuth, catchOnly, strictStrategy, publicStrategy } from "./hooks";

          const server = fastify();
          server.route({ method: "GET", url: "/a-early-return", onRequest: earlyReturn, handler: async () => [] });
          server.route({ method: "GET", url: "/b-braceless", onRequest: braceless, handler: async () => [] });
          server.route({ method: "GET", url: "/c-nested-optional", onRequest: nestedOptional, handler: async () => [] });
          server.route({ method: "GET", url: "/d-bracket-header", onRequest: bracketHeader, handler: async () => [] });
          server.route({ method: "GET", url: "/e-apikey-optional", onRequest: apiKeyOptional, handler: async () => [] });
          server.route({ method: "GET", url: "/f-else-branch", onRequest: elseBranch, handler: async () => [] });
          server.route({ method: "GET", url: "/g-guest-only", onRequest: guestOnly, handler: async () => [] });
          server.route({ method: "GET", url: "/h-optional-opt", onRequest: verifyAuthOpt({ optional: true }), handler: async () => [] });
          server.route({ method: "GET", url: "/i-anon-mode", onRequest: verifyModes(["anonymous", "jwt"]), handler: async () => [] });
          server.route({ method: "GET", url: "/j-ratelimit", onRequest: rateLimiter, handler: async () => [] });
          server.route({ method: "GET", url: "/j-log", onRequest: [logOnly], handler: async () => [] });
          server.route({ method: "GET", url: "/j-config-ratelimit", config: { rateLimit: { max: 5 } }, handler: async () => [] });
          server.route({ method: "GET", url: "/k-guard", onRequest: requireAuth(["jwt"]), handler: async () => [] });
          server.route({ method: "GET", url: "/k-array", onRequest: [logOnly, requireAuth(["jwt"])], handler: async () => [] });
          server.route({ method: "GET", url: "/l-catch", onRequest: catchOnly, handler: async () => [] });
          server.route({ method: "GET", url: "/m-or", onRequest: server.auth([strictStrategy, publicStrategy], { relation: "or" }), handler: async () => [] });
          server.get("/m-or-short", { onRequest: server.auth([strictStrategy, publicStrategy], { relation: "or" }) }, async () => []);
          server.get("/h-optional-short", { onRequest: verifyAuthOpt({ optional: true }) }, async () => []);
          server.listen({ port: 3000 });
          JS
      }, "src/server.ts")
      # Optional identity, presence tests, guest-only, opening options and
      # `relation: "or"` with a public strategy all let an anonymous caller in.
      %w[/a-early-return /b-braceless /c-nested-optional /d-bracket-header /e-apikey-optional
        /f-else-branch /g-guest-only /h-optional-opt /h-optional-short /i-anon-mode
        /j-ratelimit /j-log /j-config-ratelimit /l-catch /m-or /m-or-short].each do |url|
        tags[url].should be_empty
      end
      tags["/k-guard"].should_not be_empty
      tags["/k-array"].should_not be_empty
    end

    it "keeps the throw rule out of plugin addHook scans" do
      tags = tag_routes.call({
        "src/app.ts" => <<-JS,
          import Fastify from "fastify";

          const app = Fastify();

          app.register(async (admin) => {
            admin.addHook("onRequest", async (req) => {
              if (req.url.startsWith("/admin/") && !req.user) throw new UnauthorizedError("login");
            });
            admin.get("/admin/users", async () => []);
            admin.get("/health", async () => "ok");
            admin.route({ method: "GET", url: "/public-info", config: { public: true }, handler: async () => "" });
          });

          app.register(async (api) => {
            api.addHook("onRequest", async (req) => {
              if (req.routeOptions.config.public) return;
              if (!req.user) throw new UnauthorizedError("login");
            });
            api.route({ method: "GET", url: "/api/open", config: { public: true }, handler: async () => "" });
            api.route({ method: "GET", url: "/api/closed", handler: async () => "" });
            api.get("/api/open-short", { config: { public: true } }, async () => "");
          });

          app.listen({ port: 3000 });
          JS
      }, "src/app.ts")
      tags.values.all?(&.empty?).should be_true
      tags = tag_routes.call({
        "src/app.ts" => <<-JS,
          import Fastify from "fastify";
          const app = Fastify();
          app.addHook("onRequest", async (req) => {
            const token = req.headers.authorization;
            if (!token) return;
            const session = await lookup(token);
            if (session.revoked) throw new UnauthorizedError("revoked");
            req.auth = session;
          });
          app.get("/public/status", async () => "ok");
          app.route({ method: "GET", url: "/public/docs", handler: async () => "" });
          app.listen({ port: 3000 });
          JS
      }, "src/app.ts")
      tags["/public/status"].should be_empty
      tags["/public/docs"].should be_empty
    end

    it "credits no bypass the app does not declare, and stays open on every widening attack" do
      tags = tag_routes.call({
        "src/hooks.ts" => <<-JS,
          import { UnauthorizedError } from "./errors";

          // W1: flag derived from route config by another hook.
          export const markOpen = async (req) => {
            req.skipChecks = Boolean(req.routeOptions.config.open);
          };
          export const flagFromConfig = (req, _res, done) => {
            if (req.skipChecks) return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };

          // W2: GET is public.
          export const getIsPublic = (req, _res, done) => {
            if (req.method === "GET") return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };

          // W3: env setting.
          export const envBypass = (req, _res, done) => {
            if (process.env.DISABLE_AUTH) return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };

          // W4: local alias of the url.
          export const urlAlias = (req, _res, done) => {
            const u = req.url;
            if (u.startsWith("/health")) return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };

          // W5: raw url and optional-chained route config.
          export const rawUrl = (req, _res, done) => {
            if (req.raw.url === HEALTH) return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };
          export const optChainConfig = (req, _res, done) => {
            if (req.routeOptions?.config?.skip) return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };

          // W6: destructured url / method.
          export const destructured = (req, _res, done) => {
            const { url, method } = req;
            if (method === "OPTIONS" || url === HEALTH) return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };

          // W7: client body flag (preHandler: body is parsed).
          export const bodyFlag = (req, _res, done) => {
            if (req.body?.preview) return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };

          // W8: bracket access to route config.
          export const bracketConfig = (req, _res, done) => {
            if (req["routeOptions"]["config"]["skip"]) return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };

          // W9: req.is404 / req.host (Fastify 5) / req.ip.
          export const hostBypass = (req, _res, done) => {
            if (req.host === INTERNAL_HOST) return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };

          // W10: real strict guard (control).
          export const strict = (req, _res, done) => {
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };

          // W11: infisical's exact shape (control).
          export const verifyAuth =
            (modes: string[]) =>
            (req, _res, done) => {
              if (req.shouldForwardWritesToPrimaryInstance && req.method !== "GET") {
                return done();
              }
              if (!req.auth) throw new UnauthorizedError({ message: "Token missing" });
              done();
            };

          // W12: strategies for fastify-auth default relation (or).
          export const publicStrategy = (req, _res, done) => done();

          // W13: session object always exists with @fastify/session.
          export const sessionObj = (req, _res, done) => {
            if (!req.session) throw new UnauthorizedError("no session");
            done();
          };

          // W14: param named differently, flag bypass.
          export const methodFlag = (request, _res, done) => {
            if (request.method === "HEAD" || request.method === "GET") return done();
            if (!request.user) throw new UnauthorizedError("login");
            done();
          };
          JS
        "src/server.ts" => <<-JS,
          import fastify from "fastify";
          import { markOpen, flagFromConfig, getIsPublic, envBypass, urlAlias, rawUrl, optChainConfig, destructured, bodyFlag, bracketConfig, hostBypass, strict, verifyAuth, publicStrategy, sessionObj, methodFlag } from "./hooks";

          const server = fastify();
          server.addHook("onRequest", markOpen);
          server.route({ method: "GET", url: "/w1-open-config", config: { open: true }, onRequest: flagFromConfig, handler: async () => [] });
          server.route({ method: "GET", url: "/w2-get", onRequest: getIsPublic, handler: async () => [] });
          server.route({ method: "POST", url: "/w2-post", onRequest: getIsPublic, handler: async () => [] });
          server.route({ method: "GET", url: "/w3-env", onRequest: envBypass, handler: async () => [] });
          server.route({ method: "GET", url: "/w4-alias", onRequest: urlAlias, handler: async () => [] });
          server.route({ method: "GET", url: "/w5-raw", onRequest: rawUrl, handler: async () => [] });
          server.route({ method: "GET", url: "/w5-optchain", onRequest: optChainConfig, handler: async () => [] });
          server.route({ method: "GET", url: "/w6-destructured", onRequest: destructured, handler: async () => [] });
          server.route({ method: "POST", url: "/w7-body", preHandler: bodyFlag, handler: async () => [] });
          server.route({ method: "GET", url: "/w8-bracket", onRequest: bracketConfig, handler: async () => [] });
          server.route({ method: "GET", url: "/w9-host", onRequest: hostBypass, handler: async () => [] });
          server.route({ method: "GET", url: "/w10-strict", onRequest: strict, handler: async () => [] });
          server.route({ method: "GET", url: "/w11-verify", onRequest: verifyAuth(["jwt"]), handler: async () => [] });
          server.route({ method: "GET", url: "/w12-default-or", onRequest: server.auth([strict, publicStrategy]), handler: async () => [] });
          server.route({ method: "GET", url: "/w13-session", onRequest: sessionObj, handler: async () => [] });
          server.route({ method: "GET", url: "/w14-method", onRequest: methodFlag, handler: async () => [] });
          server.listen({ port: 3000 });
          JS
      }, "src/server.ts")
      tags["/w10-strict"].should eq(["Protected by Fastify onRequest strict"])
      tags.each { |url, found| found.should be_empty unless url == "/w10-strict" }
    end

    it "settles a declared request-flag bypass against the route's method" do
      tags = tag_routes.call({
        "src/plugins/inject.ts" => <<-JS,
          export const inject = async (server, opt) => {
            server.decorateRequest("shouldForwardWritesToPrimaryInstance", Boolean(opt.forward));
            server.decorateRequest("previewOnly", false);
            server.decorateRequest("readReplica", false);
          };
          JS
        "src/plugins/mark.ts" => <<-JS,
          export const mark = async (req) => {
            req.previewOnly = Boolean(req.body?.preview);
          };
          JS
        "src/hooks.ts" => <<-JS,
          export const verifyAuth =
            (modes: string[]) =>
            (req, _res, done) => {
              if (req.shouldForwardWritesToPrimaryInstance && req.method !== "GET") {
                return done();
              }
              if (!req.auth) throw new UnauthorizedError({ message: "Token missing" });
              done();
            };
          export const assignedFlag = (req, _res, done) => {
            if (req.previewOnly) return done();
            if (!req.auth) throw new UnauthorizedError("login");
            done();
          };
          export const readsOnGet = (req, _res, done) => {
            if (req.method === "GET" && req.readReplica) return done();
            if (!req.auth) throw new UnauthorizedError("login");
            done();
          };
          export const plainFlag = (req, _res, done) => {
            if (req.readReplica) return done();
            if (!req.auth) throw new UnauthorizedError("login");
            done();
          };
          JS
        "src/server.ts" => <<-JS,
          import { assignedFlag, plainFlag, readsOnGet, verifyAuth } from "./hooks";
          server.route({ method: "GET", url: "/secrets", onRequest: verifyAuth(["jwt"]), handler: async () => [] });
          server.route({ method: "POST", url: "/secrets-write", onRequest: verifyAuth(["jwt"]), handler: async () => [] });
          server.route({ method: "GET", url: "/preview", onRequest: assignedFlag, handler: async () => [] });
          server.route({ method: "GET", url: "/replica-get", onRequest: readsOnGet, handler: async () => [] });
          server.route({ method: "POST", url: "/replica-post", onRequest: readsOnGet, handler: async () => [] });
          server.route({ method: "GET", url: "/plain-flag", onRequest: plainFlag, handler: async () => [] });
          JS
      }, "src/server.ts")
      note = " (a request-flag early return can bypass it)"
      # `!== "GET"`: the bypass never applies to a GET route.
      tags["/secrets"].should eq(["Protected by Fastify onRequest verifyAuth"])
      tags["/secrets-write"].should eq(["Protected by Fastify onRequest verifyAuth#{note}"])
      # A flag some hook assigns from the request is request input.
      tags["/preview"].should be_empty
      tags["/replica-get"].should eq(["Protected by Fastify onRequest readsOnGet#{note}"])
      tags["/replica-post"].should eq(["Protected by Fastify onRequest readsOnGet"])
      tags["/plain-flag"].should eq(["Protected by Fastify onRequest plainFlag#{note}"])
    end

    it "rejects flags set at request time or computed by their decoration" do
      tags = tag_routes.call({
        "src/hooks.ts" => <<-JS,
          import { UnauthorizedError } from "./errors";

          export const viaSetDecorator = (req, _res, done) => {
            if (req.skipA) return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };
          export const viaObjectAssign = (req, _res, done) => {
            if (req.skipB) return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };
          export const viaBracket = (req, _res, done) => {
            if (req.skipC) return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };
          export const viaOtherParam = (req, _res, done) => {
            if (req.skipD) return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };
          export const viaGetter = (req, _res, done) => {
            if (req.isTrusted) return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };
          export const viaMethodFn = (req, _res, done) => {
            if (req.isInternal) return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };
          export const upperMethod = (req, _res, done) => {
            if (req.forwarded && req.method.toUpperCase() !== "GET") return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };
          export const includesMethod = (req, _res, done) => {
            if (req.forwarded && ["POST", "PUT"].includes(req.method)) return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };
          export const orMethod = (req, _res, done) => {
            if (req.forwarded || req.method === "GET") return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };
          export const settingFlag = (req, _res, done) => {
            if (req.forwarded && req.method !== "GET") return done();
            if (!req.auth) throw new UnauthorizedError("Token missing");
            done();
          };
          export const strictStrategy = (req, _res, done) => {
            if (!req.user) throw new UnauthorizedError("no user");
            done();
          };
          export const strict2 = (req, _res, done) => {
            if (!req.auth) throw new UnauthorizedError("no auth");
            done();
          };
          export const publicStrategy = (req, _res, done) => done();
          JS
        "src/server.ts" => <<-JS,
          import fastify from "fastify";
          import { viaSetDecorator, viaObjectAssign, viaBracket, viaOtherParam, viaGetter, viaMethodFn, upperMethod, includesMethod, orMethod, settingFlag, strictStrategy, strict2, publicStrategy } from "./hooks";

          const server = fastify();
          server.decorateRequest("skipA", false);
          server.decorateRequest("skipB", false);
          server.decorateRequest("skipC", false);
          server.decorateRequest("skipD", false);
          server.decorateRequest("isTrusted", { getter() { return this.headers["x-trusted"] === "1"; } });
          server.decorateRequest("isInternal", function () { return this.ip === "127.0.0.1"; });
          server.decorateRequest("forwarded", Boolean(process.env.FORWARD));
          server.addHook("onRequest", async (request) => {
            request.setDecorator("skipA", Boolean(request.routeOptions.config.open));
            Object.assign(request, { skipB: Boolean(request.routeOptions.config.open) });
            const flagName = "skipC";
            request[flagName] = Boolean(request.routeOptions.config.open);
          });
          server.addHook("onRequest", async (r) => {
            r.skipD = Boolean(r.routeOptions.config.open);
          });
          const AND = { relation: "and" };
          const OR = { relation: "or" };
          server.route({ method: "GET", url: "/r-setdecorator", config: { open: true }, onRequest: viaSetDecorator, handler: async () => [] });
          server.route({ method: "GET", url: "/r-assign", config: { open: true }, onRequest: viaObjectAssign, handler: async () => [] });
          server.route({ method: "GET", url: "/r-bracket", config: { open: true }, onRequest: viaBracket, handler: async () => [] });
          server.route({ method: "GET", url: "/r-otherparam", config: { open: true }, onRequest: viaOtherParam, handler: async () => [] });
          server.route({ method: "GET", url: "/r-getter", onRequest: viaGetter, handler: async () => [] });
          server.route({ method: "GET", url: "/r-methodfn", onRequest: viaMethodFn, handler: async () => [] });
          server.route({ method: "POST", url: "/r-upper", onRequest: upperMethod, handler: async () => [] });
          server.route({ method: "POST", url: "/r-includes", onRequest: includesMethod, handler: async () => [] });
          server.route({ method: "GET", url: "/r-or", onRequest: orMethod, handler: async () => [] });
          server.route({ method: "GET", url: "/r-setting-get", onRequest: settingFlag, handler: async () => [] });
          server.route({ method: "POST", url: "/r-setting-post", onRequest: settingFlag, handler: async () => [] });
          server.route({ method: "GET", url: "/r-and-var", onRequest: server.auth([strictStrategy, strict2], AND), handler: async () => [] });
          server.route({ method: "GET", url: "/r-and-var-pub", onRequest: server.auth([strictStrategy, publicStrategy], AND), handler: async () => [] });
          server.route({ method: "GET", url: "/r-or-var", onRequest: server.auth([strictStrategy, publicStrategy], OR), handler: async () => [] });
          server.listen({ port: 3000 });
          JS
      }, "src/server.ts")
      note = " (a request-flag early return can bypass it)"
      %w[/r-setdecorator /r-assign /r-bracket /r-otherparam /r-getter /r-methodfn
        /r-upper /r-includes /r-or /r-and-var-pub /r-or-var].each { |url| tags[url].should be_empty }
      tags["/r-setting-get"].should eq(["Protected by Fastify onRequest settingFlag"])
      tags["/r-setting-post"].should eq(["Protected by Fastify onRequest settingFlag#{note}"])
      tags["/r-and-var"].should_not be_empty
    end

    it "anchors the absence test to its own if, not an earlier one" do
      tags = tag_routes.call({
        "src/hooks.ts" => <<-JS,
          export const strict = (req, _res, done) => {
            if (req.headers.authorization) req.log.debug("token sent");
            if (!req.user) {
              throw new UnauthorizedError("login");
            }
            done();
          };
          JS
        "src/server.ts" => <<-JS,
          import fastify from "fastify";
          import { strict } from "./hooks";
          const server = fastify();
          server.route({ method: "GET", url: "/strict", onRequest: strict, handler: async () => [] });
          JS
      }, "src/server.ts")
      tags["/strict"].should eq(["Protected by Fastify onRequest strict"])
    end

    it "reads a hook with tens of thousands of nested ifs in linear time" do
      body = String.build do |io|
        io << "export const big = (req, _res, done) => {\n  if (q) {\n"
        40_000.times { |i| io << "    if (a" << i << ") b" << i << "(x);\n" }
        io << "    if (!req.user) { throw new UnauthorizedError('x'); }\n  }\n  done();\n};\n"
      end
      started = Time.instant
      tags = tag_routes.call({
        "src/hooks.ts"  => body,
        "src/server.ts" => %(import { big } from "./hooks";\nserver.route({ method: "GET", url: "/big", onRequest: big, handler: async () => [] });\n),
      }, "src/server.ts")
      tags["/big"].should be_empty
      (Time.instant - started).should be < 10.seconds
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

  # Wiki.js: the handler's first check is a 401 to a caller who is not there.
  it "reads a Fastify handler that refuses an absent caller first" do
    tmpdir = File.tempname("fastify_handler_check")
    Dir.mkdir_p(tmpdir)
    file = File.join(tmpdir, "users.ts")
    routes = [
      {"get", "/profile", "async (req, reply) => {\n  reply.preventCache()\n  // the session's user\n  const userId = requestUserId(req)\n  if (!userId) {\n    return reply.unauthorized()\n  }\n  return getProfile(userId)\n}"},
      {"post", "/ideas", "async (req: FastifyRequest<{ Body: Idea, Params: P }>, reply) => {\n  const actor = actorFrom(req)\n  const user = await requestUser(req)\n  if (!actor || !user) {\n    return reply.unauthorized('Sign in')\n  }\n}"},
      {"get", "/mentions", "async (req, reply) => {\n  if (!hasUserSession(req)) return reply.code(401).send()\n}"},
      {"put", "/opts", "{ schema: {}, handler: async (req, reply) => {\n  if (!requestUserId(req)) {\n    throw app.httpErrors.unauthorized()\n  }\n} }"},
      # Something runs first, an `&&`, a value not read off the request, a 404,
      # a check that refuses the signed-in, a reply already sent.
      {"post", "/e", "async (req, reply) => {\n  if (!isAnonymous(req)) return reply.code(401).send()\n}"},
      {"post", "/f", "async (req, reply) => {\n  reply.send()\n  if (!requestUserId(req)) return reply.unauthorized()\n}"},
      {"post", "/a", "async (req, reply) => {\n  log(req.body)\n  const userId = requestUserId(req)\n  if (!userId) {\n    return reply.unauthorized()\n  }\n}"},
      {"post", "/b", "async (req, reply) => {\n  const userId = requestUserId(req)\n  if (!userId && strict) {\n    return reply.unauthorized()\n  }\n}"},
      {"post", "/c", "async (req, reply) => {\n  const page = pages[req.params.id]\n  if (!page) {\n    return reply.unauthorized()\n  }\n}"},
      {"post", "/d", "async (req, reply) => {\n  const page = loadPage(req)\n  if (!page) {\n    return reply.notFound()\n  }\n}"},
    ]
    lines = [] of String
    starts = routes.map do |verb, route, handler|
      start = lines.size + 1
      call = handler.starts_with?('{') ? "app.#{verb}('#{route}', #{handler})" : "app.#{verb}('#{route}', { schema: { summary: 'x' } }, #{handler})"
      lines.concat(call.split('\n'))
      start
    end
    File.write(file, lines.join('\n'))
    CodeLocator.instance.register_path(file)
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    endpoints = routes.map_with_index do |(verb, route, _), idx|
      details = Details.new(PathInfo.new(file, starts[idx]))
      details.technology = "js_fastify"
      Endpoint.new(route, verb.upcase, [] of Param, details)
    end

    JsMiscAuthTagger.new(noir_options).perform(endpoints)

    endpoints[0].tags.map(&.description).should eq(["Protected by Fastify handler check `if (!userId)` (replies 401)"])
    endpoints[1..3].each(&.tags.size.should(eq(1)))
    endpoints[4..].each(&.tags.should(be_empty))
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end
end
