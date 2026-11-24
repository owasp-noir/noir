require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"
require "../../../../src/analyzer/analyzers/javascript/express"

# Scans `files` (name => source) as an Express project and runs the auth
# tagger, as a scan does.
private def express_requires(files : Hash(String, String)) : Hash(String, Tag?)
  dir = File.tempname("express_requires")
  files.each do |name, text|
    path = File.join(dir, name)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, text)
  end
  CodeLocator.instance.clear_all
  Noir::JSHandlerResolver.reset
  Dir.glob("#{dir}/**/*").each { |path| CodeLocator.instance.register_path(path) unless File.directory?(path) }
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(dir)])
  # A route registered twice is one endpoint with two code paths, as the
  # optimizer folds it before tagging.
  endpoints = Analyzer::Javascript::Express.new(options).analyze.group_by { |row| {row.method, row.url} }.values.map do |rows|
    rows[1..].each { |other| other.details.code_paths.each { |path| rows[0].details.add_path(path) } }
    rows[0]
  end
  endpoints.map! do |row|
    details = row.details
    details.technology = "js_express"
    row.details = details
    row
  end
  endpoints = ExpressAuthTagger.new(options).perform(endpoints)
  endpoints.to_h { |row| {"#{row.method} #{row.url}", row.tags.find { |tag| tag.tagger == "express_auth" }} }
ensure
  FileUtils.rm_rf(dir) if dir
end

private def requirement(tag : Tag?) : String?
  tag.try(&.requires).try do |clauses|
    clauses.map do |clause|
      atoms = clause.any_of.map { |atom| atom.kind.unresolved? ? "unresolved:#{atom.value}" : atom.to_s }
      atoms.size > 1 ? "(#{atoms.join(" | ")})" : atoms[0]
    end.join(" & ")
  end
end

describe "ExpressAuthTagger requires" do
  it "reads Passport, express-jwt and express-basic-auth written at the route or bound once in the module" do
    tags = express_requires({"app.js" => <<-JS})
      const express = require('express');
      const passport = require('passport');
      const { expressjwt } = require('express-jwt');
      const basicAuth = require('express-basic-auth');
      const app = express();
      const admin = basicAuth({ users: { admin: 'x' } });
      const optional = expressjwt({ secret: 's' }).unless({ path: ['/login'] });
      app.get('/passport', passport.authenticate('jwt', { session: false }), (req, res) => res.json({}));
      app.get('/session', passport.authenticate('session'), (req, res) => res.json({}));
      app.get('/token', expressjwt({ secret: 's', algorithms: ['HS256'] }), (req, res) => res.json({}));
      app.get('/basic', admin, (req, res) => res.json({}));
      app.get('/bound-unless', optional, (req, res) => res.json({}));
      JS
    requirement(tags["GET /passport"]).should eq("authenticated")
    requirement(tags["GET /session"]).should eq("unresolved:passport.authenticate('session')")
    requirement(tags["GET /token"]).should eq("authenticated")
    requirement(tags["GET /basic"]).should eq("authenticated")
    # The binding goes on past the call: not read, so the default stands.
    tags["GET /bound-unless"].should_not be_nil
    requirement(tags["GET /bound-unless"]).should be_nil
  end

  it "joins every guard of the chain, not only the one the description names" do
    tags = express_requires({"app.js" => <<-JS})
      const express = require('express');
      const passport = require('passport');
      const { requiredScopes } = require('express-oauth2-jwt-bearer');
      const app = express();
      function adminOnly(req, res, next) {
        if (!req.user || req.user.role !== 'admin') return res.sendStatus(403);
        next();
      }
      app.use('/admin', passport.authenticate('jwt', { session: false }));
      app.get('/admin/users', adminOnly, (req, res) => res.json({}));
      app.get('/admin/scoped', requiredScopes('read:users'), (req, res) => res.json({}));
      app.get('/open', (req, res) => res.json({}));
      JS
    # The description names `adminOnly`; the Passport mount above it and the
    # unread role check both count.
    users = tags["GET /admin/users"].not_nil!
    users.description.should contain("adminOnly")
    requirement(users).should eq("authenticated & unresolved:adminOnly")
    requirement(tags["GET /admin/scoped"]).should eq("authenticated & scope:read:users")
    tags["GET /open"].should be_nil
  end

  it "leaves a middleware that only shares a package export's name at the default" do
    tags = express_requires({"app.js" => <<-JS})
      const express = require('express');
      const app = express();
      function ensureLoggedIn() {
        return (req, res, next) => (req.user ? next() : res.sendStatus(401));
      }
      function requireAuth(req, res, next) {
        if (!req.user) return res.sendStatus(401);
        next();
      }
      app.get('/named', ensureLoggedIn(), (req, res) => res.json({}));
      app.get('/custom', requireAuth, (req, res) => res.json({}));
      JS
    tags["GET /named"].should_not be_nil
    requirement(tags["GET /named"]).should be_nil
    tags["GET /custom"].should_not be_nil
    requirement(tags["GET /custom"]).should be_nil
  end

  it "reads a router's own use() only for the routes registered after it" do
    tags = express_requires({"app.js" => <<-JS})
      const express = require('express');
      const passport = require('passport');
      const { ensureLoggedIn } = require('connect-ensure-login');
      const app = express();
      const router = express.Router();
      router.get('/before', ensureLoggedIn(), (req, res) => res.json({}));
      router.use(passport.authenticate(['jwt', 'anonymous']));
      router.get('/after', ensureLoggedIn(), (req, res) => res.json({}));
      app.use('/r', router);
      JS
    requirement(tags["GET /r/before"]).should eq("authenticated")
    requirement(tags["GET /r/after"]).should eq("unresolved:passport.authenticate(['jwt', 'anonymous']) & authenticated")
  end

  it "keeps the default where another chain may serve the route or a mount prefix is unread" do
    tags = express_requires({
      "config.js" => "module.exports = { base: process.env.BASE };",
      "app.js"    => <<-JS,
        const express = require('express');
        const passport = require('passport');
        const { base } = require('./config');
        const app = express();
        const router = express.Router();
        router.get('/direct', passport.authenticate('jwt', { session: false }), (req, res) => res.json({}));
        app.use(base, router);
        app.get('/twice', passport.authenticate('jwt', { session: false }), (req, res) => res.json({}));
        app.get('/twice', passport.authenticate('jwt', { session: false }), (req, res) => res.json({}));
        JS
    })
    tags["GET /direct"].should_not be_nil
    requirement(tags["GET /direct"]).should be_nil
    tags["GET /twice"].should_not be_nil
    requirement(tags["GET /twice"]).should be_nil
  end

  it "keeps every unread step of the chain, and drops only steps that refuse nobody" do
    tags = express_requires({
      "app.js" => <<-JS,
        const express = require('express');
        const cors = require('cors');
        const passport = require('passport');
        const { requireRole } = require('acl-kit');
        const app = express();
        function stamp(req, res, next) { req.at = Date.now(); next(); }
        function requireAdmin(req, res, next) { if (req.user && req.user.role !== 'admin') return res.sendStatus(403); next(); }
        app.get('/package', passport.authenticate('jwt', { session: false }), requireRole('admin'), (req, res) => res.json({}));
        app.get('/inline', passport.authenticate('jwt', { session: false }), (req, res, next) => { if (!req.user.admin) throw new Error('no'); next(); }, (req, res) => res.json({}));
        app.get('/presence', passport.authenticate('jwt', { session: false }), requireAdmin, (req, res) => res.json({}));
        app.get('/quiet', cors(), express.json(), stamp, passport.authenticate('jwt', { session: false }), (req, res) => res.json({}));
        app.use(function adminOnly(req, res, next) { if (!req.user.admin) return res.sendStatus(403); next(); });
        app.get('/after-use', passport.authenticate('jwt', { session: false }), (req, res) => res.json({}));
        JS
    })
    requirement(tags["GET /package"]).should eq("authenticated & unresolved:requireRole('admin')")
    requirement(tags["GET /inline"]).should eq("authenticated & unresolved:(req, res, next) => { if (!req.user.admin) throw new Error('no'); next(); }")
    requirement(tags["GET /presence"]).should eq("authenticated & unresolved:requireAdmin")
    requirement(tags["GET /quiet"]).should eq("authenticated")
    requirement(tags["GET /after-use"]).should eq("unresolved:function adminOnly(req, res, next) { if (!req.user.admin) return res.sendStatus(403); next(); } & authenticated")
  end

  it "reads a Passport strategy name by what the app registers under it" do
    tags = express_requires({
      "app.js" => <<-JS,
        const express = require('express');
        const passport = require('passport');
        const AnonymousStrategy = require('passport-anonymous').Strategy;
        const { Strategy: JwtStrategy } = require('passport-jwt');
        passport.use('bearer', new AnonymousStrategy());
        passport.use('jwt', new JwtStrategy({}, verify));
        const app = express();
        app.get('/bearer', passport.authenticate('bearer', { session: false }), (req, res) => res.json({}));
        app.get('/jwt', passport.authenticate('jwt', { session: false }), (req, res) => res.json({}));
        JS
    })
    tags["GET /bearer"].should_not be_nil
    requirement(tags["GET /bearer"]).should be_nil
    requirement(tags["GET /jwt"]).should eq("authenticated")
  end
end
