require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"
require "../../../../src/analyzer/analyzers/javascript/express"
require "../../../../src/ai_context/augmentor"
require "../../../../src/cli/commands/query"
require "../../../../src/output_builder/common"
require "../../../../src/optimizer/optimizer"

private def express_guard_rows(source : String, extra : Hash(String, String) = {} of String => String) : Array(Endpoint)
  dir = File.tempname("express_guard_resolution")
  Dir.mkdir_p(dir)
  file = File.join(dir, "app.js")
  File.write(file, source)
  extra.each { |name, text| File.write(File.join(dir, name), text) }
  CodeLocator.instance.clear_all
  Noir::JSHandlerResolver.reset
  Dir.glob("#{dir}/*").each { |path| CodeLocator.instance.register_path(path) }
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(dir)])
  endpoints = Analyzer::Javascript::Express.new(options).analyze.select { |row| row.method == "GET" && !row.url.includes?('*') }
  endpoints.sort_by! { |row| row.details.code_paths.first.line || 0 }
  endpoints.map! do |row|
    details = row.details
    details.technology = "js_express"
    row.details = details
    row.resolution = {"prefix" => Endpoint::RESOLUTION_UNRESOLVED} if row.url == "/prefix"
    row
  end
  NoirTaggers.run_tagger(endpoints, options, "express_auth")
  endpoints
ensure
  FileUtils.rm_rf(dir) if dir
end

describe "ExpressAuthTagger guard resolution (#3567)" do
  it "marks names, Passport, JWT and imported libraries, but not a followed refusal" do
    source = <<-JS
      const { expressjwt: token } = require('express-jwt');
      const basicAuth = require('express-basic-auth');
      const { requiresAuth } = require('express-openid-connect');
      const oidc = requiresAuth();
      const bound = basicAuth({ users: {} });
      function checkpoint(req, res, next) {
        if (!req.user) return res.sendStatus(401);
        const route = req.path;
        next();
      }
      function permit(req, res, next) {
        if (!req.account) throw new ForbiddenError();
        next();
      }
      function nextError(req, res, next) {
        if (!req.user) return next(new Error());
        next();
      }
      function unknownError(req, res, next) {
        if (!req.user) return next(errorFor(req));
        next();
      }
      function statusOnly(req, res, next) {
        if (maintenance) return res.sendStatus(403);
        next();
      }
      app.get('/name', requireAuth, h);
      app.get('/passport', passport.authenticate('jwt'), h);
      app.get('/jwt', expressjwt({}), h);
      app.get('/alias', token({}), h);
      app.get('/basic', basicAuth({}), h);
      app.get('/bound', bound, h);
      app.get('/body', checkpoint, h);
      app.get('/throw', permit, h);
      app.get('/next-error', nextError, h);
      app.get('/unknown-error', unknownError, h);
      app.get('/status-shape', statusOnly, h);
      app.get('/prefix', requireAuth, h);
      app.get('/optional', token({ credentialsRequired: false }), h);
      app.get('/login', passport.authenticate('local'), h);
      app.get('/oidc', oidc, h);
      app.get('/open', h);
      JS
    rows = express_guard_rows(source).to_h { |ep| {ep.url, ep} }
    %w[name passport jwt alias basic bound status-shape unknown-error].each do |name|
      rows["/#{name}"].tags.map(&.name).should eq(["auth"])
      rows["/#{name}"].resolution.should eq({"guard" => "heuristic"})
    end
    %w[body throw next-error].each do |name|
      rows["/#{name}"].tags.map(&.name).should eq(["auth"])
      rows["/#{name}"].resolution.should be_nil
      JSON.parse(rows["/#{name}"].to_json).as_h.has_key?("resolution").should be_false
    end
    rows["/prefix"].resolution.should eq({"prefix" => "unresolved", "guard" => "heuristic"})
    %w[optional login oidc open].each do |name|
      rows["/#{name}"].tags.should be_empty
      rows["/#{name}"].resolution.should be_nil
    end
  end

  it "keeps the first tag while one followed step establishes mixed and array guards" do
    rows = express_guard_rows(<<-JS)
      function checkpoint(req, res, next) {
        if (!req.user) return res.sendStatus(401);
        next();
      }
      const steps = [requireAuth, checkpoint];
      app.get('/mixed', requireAuth, checkpoint, h);
      app.get('/array', [requireAuth, checkpoint], h);
      app.get('/bound-array', steps, h);
      app.get('/matched-array', [requireAuth], h);
      JS
    rows.first(3).each do |row|
      row.tags.size.should eq(1)
      row.tags.first.description.should contain("requireAuth")
      row.resolution.should be_nil
    end
    rows.last.resolution.should eq({"guard" => "heuristic"})
  end

  it "marks receiver, mount, all and helper scopes even with a read body" do
    rows = express_guard_rows(<<-JS)
      const app = express();
      const router = express.Router();
      function checkpoint(req, res, next) {
        if (!req.user) return res.sendStatus(401);
        next();
      }
      router.use(checkpoint);
      router.get('/receiver', h);
      app.use('/mounted', checkpoint, router);
      app.get('/mounted/items', h);
      app.all('/all/*', checkpoint);
      app.get('/all/items', h);
      function setup(router, path, guard, handler) { router.get(path, guard, handler); }
      setup(app, '/helper', checkpoint, h);
      JS
    rows.size.should eq(4)
    rows.each do |row|
      row.tags.map(&.name).should eq(["auth"])
      row.resolution.should eq({"guard" => "heuristic"})
    end
  end

  it "follows imports but marks wrapper shapes, settings and library bodies" do
    source = <<-JS
      const { checkpoint } = require('./gate');
      const { wrapped } = require('./gate');
      function secure(fn) {
        return (req, res, next) => {
          if (!req.user) return res.sendStatus(401);
          fn(req, res, next);
        };
      }
      function forward(fn) { return (req, res, next) => fn(req, res, next); }
      function configurable(req, res, next) {
        if (config.private) { if (!req.user) return res.sendStatus(401); }
        next();
      }
      function library(req, res, next) { return expressjwt({})(req, res, next); }
      const config = {};
      app.get('/import', checkpoint, h);
      app.get('/wrapper', secure(h));
      app.get('/forward', forward(checkpoint), h);
      app.get('/nested-wrapper', forward(secure(h)));
      app.get('/export-wrapper', wrapped, h);
      app.get('/setting', configurable, h);
      app.get('/library-body', library, h);
      JS
    extra = {"gate.js" => <<-JS}
      export function checkpoint(req, res, next) {
        if (!req.user) return res.sendStatus(401);
        next();
      }
      export const wrapped = asyncHandler(checkpoint);
      JS
    rows = express_guard_rows(source, extra)
    rows.first(1).each do |row|
      row.tags.map(&.name).should eq(["auth"])
      row.resolution.should be_nil
    end
    rows[1..].each do |row|
      row.tags.map(&.name).should eq(["auth"])
      row.resolution.should eq({"guard" => "heuristic"})
    end
  end

  it "follows handler checks and refusing returns but marks a service instance binding" do
    rows = express_guard_rows(<<-JS)
      function denied(req, res) { res.sendStatus(401); }
      function checkpoint(req, res, next) {
        if (!req.loggedIn) return denied(req, res);
        next();
      }
      function guarded(req, res) {
        if (!req.user) return res.sendStatus(401);
        res.json({});
      }
      class Gate {
        check() {
          if (!this.accountability.user) throw new Error();
        }
      }
      async function service(req, res) {
        const gate = new Gate({ accountability: req.accountability });
        await gate.check();
        res.json({});
      }
      app.get('/return', checkpoint, h);
      app.get('/handler', guarded);
      app.get('/service', service);
      JS
    rows.first(2).each do |row|
      row.tags.map(&.name).should eq(["auth"])
      row.resolution.should be_nil
    end
    rows.last.tags.map(&.name).should eq(["auth"])
    rows.last.resolution.should eq({"guard" => "heuristic"})
  end
  it "carries Express marks through query filters, rendering, serialization and merge" do
    rows = express_guard_rows(<<-JS)
      function checkpoint(req, res, next) {
        if (!req.user) return res.sendStatus(401);
        next();
      }
      app.get('/matched', requireAuth, h);
      app.get('/followed', checkpoint, h);
      app.get('/open', h);
      JS
    NoirAIContext.apply(rows)
    included = Noir::CLI::QueryCommand.parse_filters(["--guard", "--resolution", "heuristic"])
    excluded = Noir::CLI::QueryCommand.parse_filters(["--exclude", "resolution=heuristic", "--guard"])
    selected = Noir::CLI::Inspect.query(rows, included.filters, false)
    selected.map(&.url).should eq(["/matched"])
    Noir::CLI::Inspect.query(rows, excluded.filters, false, excluded.excludes).map(&.url).should eq(["/followed"])
    selected.first.to_text.should contain("resolution=guard:heuristic")
    JSON.parse(selected.first.to_json)["resolution"]["guard"].should eq("heuristic")
    full = Noir::CLI::Inspect.query(rows, included.filters, true).first
    JSON.parse(full.to_json)["endpoint"]["resolution"]["guard"].should eq("heuristic")
    Endpoint.from_json(rows.first.to_json).resolution.should eq({"guard" => "heuristic"})
    Endpoint.from_yaml(rows.first.to_yaml).resolution.should eq({"guard" => "heuristic"})
    options = create_test_options
    options["color"] = YAML::Any.new(false)
    builder = OutputBuilderCommon.new(options)
    builder.io = IO::Memory.new
    builder.print(rows)
    builder.io.to_s.should contain("guard heuristic")
    duplicate = Endpoint.new("/matched", "GET", rows.first.details)
    duplicate.resolution = {"prefix" => Endpoint::RESOLUTION_UNRESOLVED}
    optimizer = EndpointOptimizer.new(NoirLogger.new(false, false, false, false), options)
    [[rows.first, duplicate], [duplicate, rows.first]].each do |pair|
      optimizer.optimize_endpoints(pair).first.resolution.should eq({"prefix" => "unresolved", "guard" => "heuristic"})
    end
  end

  it "records delegated refusals and helper shapes without treating a library call as followed" do
    rows = express_guard_rows(<<-JS)
      function loadIdentity(req, res) {
        if (!req.user) {
          res.sendStatus(401);
          return null;
        }
        return req.user;
      }
      function checkpoint(req, res, next) {
        const user = loadIdentity(req, res);
        if (!user) return;
        next();
      }
      function helperShape(req, res, next) {
        if (!req.user) return sendError(res, 401);
        next();
      }
      app.get('/delegated', checkpoint, h);
      app.get('/helper-shape', helperShape, h);
      JS
    rows.map(&.tags.map(&.name)).should eq([["auth"], ["auth"]])
    rows.first.resolution.should be_nil
    rows.last.resolution.should eq({"guard" => "heuristic"})
  end
  it "marks shadowed names and refusals behind unread conditions" do
    rows = express_guard_rows(<<-JS)
      function checkpoint(req, res, next) {
        if (!req.user) return res.sendStatus(401);
        next();
      }
      function conditional(req, res, next) {
        if (!req.user && enabled) return res.sendStatus(401);
        next();
      }
      function statusOnly(req, res, next) {
        if (!req.user) res.status(401);
        next();
      }
      let flag = false;
      function nested(req, res, next) {
        if (!req.user) { if (flag) return res.sendStatus(401); }
        next();
      }
      function predicate(req, res, next) {
        if (!req.isAuthenticated()) return res.sendStatus(401);
        next();
      }
      function calledFirst(req, res, next) {
        servePrivate(req, res);
        if (!req.user) return res.sendStatus(401);
        next();
      }
      function assignedFirst(req, res, next) {
        req.user = {};
        if (!req.user) return res.sendStatus(401);
        next();
      }
      function inverted(req, res, next) {
        if (!req.user === false) return res.sendStatus(401);
        next();
      }
      function routes(checkpoint) {
        app.get('/shadowed', checkpoint, h);
      }
      app.get('/conditional', conditional, h);
      app.get('/status-only', statusOnly, h);
      app.get('/inverted', inverted, h);
      app.get('/nested', nested, h);
      app.get('/predicate', predicate, h);
      app.get('/called-first', calledFirst, h);
      app.get('/assigned-first', assignedFirst, h);
      JS
    rows.each do |row|
      row.tags.map(&.name).should eq(["auth"])
      row.resolution.should eq({"guard" => "heuristic"})
    end
  end
  it "keeps post-handoff, deferred and out-of-scope refusals matched" do
    rows = express_guard_rows(<<-JS)
      function afterNext(req, res, next) {
        next();
        if (!req.user) return res.sendStatus(401);
      }
      function branchNext(req, res, next) {
        if (!req.user) { next(); return res.sendStatus(401); }
        next();
      }
      function deferred(req, res, next) {
        if (!req.user) { setTimeout(() => res.sendStatus(401), 100); }
        next();
      }
      function unrelated() {
        function checkpoint(req, res, next) {
          if (!req.user) return res.sendStatus(401);
          next();
        }
      }
      function guarded(req, res) {
        if (!req.user) return res.sendStatus(401);
        res.send('private');
      }
      function register(guarded) {
        app.get('/shadowed-handler', guarded);
      }
      app.get('/after-next', afterNext, h);
      app.get('/branch-next', branchNext, h);
      app.get('/deferred', deferred, h);
      app.get('/out-of-scope', checkpoint, h);
      JS
    rows.each do |row|
      row.tags.map(&.name).should eq(["auth"])
      row.resolution.should eq({"guard" => "heuristic"})
    end
  end
  it "marks a private function selected instead of a module's export" do
    source = <<-JS
      const checkpoint = require('./gate');
      app.get('/default-export', checkpoint, h);
      JS
    extra = {"gate.js" => <<-JS}
      function checkpoint(req, res, next) {
        if (!req.user) return res.sendStatus(401);
        next();
      }
      module.exports = function open(req, res, next) { next(); };
      JS
    row = express_guard_rows(source, extra).first
    row.tags.map(&.name).should eq(["auth"])
    row.resolution.should eq({"guard" => "heuristic"})
  end
  it "marks an overwritten export and a path-exempt middleware without changing their tags" do
    source = <<-JS
      const { checkpoint } = require('./gate');
      function exempt(req, res, next) {
        if (req.path === '/health') {} else if (!req.user) { return res.sendStatus(401); }
        next();
      }
      app.get('/overwritten', checkpoint, h);
      app.get('/health', exempt, h);
      JS
    extra = {"gate.js" => <<-JS}
      function open(req, res, next) { next(); }
      exports.checkpoint = function(req, res, next) {
        if (!req.user) return res.sendStatus(401);
        next();
      };
      exports.checkpoint = open;
      JS
    express_guard_rows(source, extra).each do |row|
      row.tags.map(&.name).should eq(["auth"])
      row.resolution.should eq({"guard" => "heuristic"})
    end
  end
end

describe "ExpressAuthTagger multiline middleware" do
  it "reads the whole registration and guard definition" do
    rows = express_guard_rows(<<-JS)
      function gate(req, res, next) {
        #{"\n" * 70}
        if (!req.user) return res.sendStatus(401);
        next();
      }
      app.get('/private',
        #{"\n" * 70}
        gate, handle);
      app.get('/open', handle);
      JS
    rows.map(&.tags.map(&.name)).should eq([["auth"], [] of String])
  end
end
