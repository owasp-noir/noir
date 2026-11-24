require "../../../spec_helper"
require "../../../../src/tagger/framework_taggers/javascript/js_middleware_access"

# Each local name bound the way the line in a module would bind it.
private def imports
  JsMiddlewareAccess::Imports{
    "passport"         => {"passport", nil},
    "expressjwt"       => {"express-jwt", "expressjwt"},
    "legacyJwt"        => {"express-jwt", nil},
    "basicAuth"        => {"express-basic-auth", nil},
    "ensureLoggedIn"   => {"connect-ensure-login", "ensureLoggedIn"},
    "ensureLoggedOut"  => {"connect-ensure-login", "ensureLoggedOut"},
    "ensure"           => {"connect-ensure-login", nil},
    "auth"             => {"express-oauth2-jwt-bearer", "auth"},
    "requiredScopes"   => {"express-oauth2-jwt-bearer", "requiredScopes"},
    "scopeIncludesAny" => {"express-oauth2-jwt-bearer", "scopeIncludesAny"},
    "claimEquals"      => {"express-oauth2-jwt-bearer", "claimEquals"},
    "jwtAuthz"         => {"express-jwt-authz", nil},
    "requiresAuth"     => {"express-openid-connect", "requiresAuth"},
    "jwt"              => {"hono/jwt", "jwt"},
    "bearerAuth"       => {"hono/bearer-auth", "bearerAuth"},
    "honoBasic"        => {"hono/basic-auth", "basicAuth"},
    "local"            => {"./local", "guard"},
    "cors"             => {"cors", nil},
    "bodyParser"       => {"body-parser", nil},
    "express"          => {"express", nil},
  }
end

private def atom_text(atom : Access::Atom) : String
  atom.kind.unresolved? ? "unresolved:#{atom.value}" : atom.to_s
end

private def reading(text : String) : String?
  call = JsMiddlewareAccess.parse(text, imports) || return
  JsMiddlewareAccess.read(call).try do |cnf|
    next "passes" if cnf.empty?
    cnf.map { |clause| atoms = clause.map { |atom| atom_text(atom) }.sort!; atoms.size > 1 ? "(#{atoms.join(" | ")})" : atoms[0] }.join(" & ")
  end
end

describe JsMiddlewareAccess do
  {
    # passport: one strategy, a chain of them, the passing ones, a callback,
    # a name the app registers as some other strategy.
    "passport.authenticate('jwt', { session: false })"                => "authenticated",
    "passport.authenticate(\"bearer\")"                               => "authenticated",
    "passport.authenticate(['jwt', 'basic'], { session: false })"     => "authenticated",
    "passport.authenticate('jwt', { failWithError: true })"           => "authenticated",
    "passport.authenticate(['jwt', 'anonymous'], { session: false })" => "unresolved:passport.authenticate(['jwt', 'anonymous'], { session: false })",
    "passport.authenticate('session')"                                => "unresolved:passport.authenticate('session')",
    "passport.authenticate('jwt', (err, user) => next())"             => "unresolved:passport.authenticate('jwt', (err, user) => next())",
    "passport.authenticate('jwt', function (err, user) {})"           => "unresolved:passport.authenticate('jwt', function (err, user) {})",
    "passport.authenticate('jwt', options)"                           => nil,
    "passport.authenticate('jwt', { ...options })"                    => nil,
    "passport.authenticate('jwt', { custom: true })"                  => nil,
    "passport.authenticate('saml-admin')"                             => nil,
    "passport.authenticate(strategy)"                                 => nil,
    "passport.authenticate(['jwt', name])"                            => nil,
    "passport.authenticate('jwt')(req, res, next)"                    => nil,
    "passport.session()"                                              => "passes",
    "passport.initialize()"                                           => "passes",
    # express-jwt: required by default, optional, unread options, `.unless`.
    "expressjwt({ secret: 's', algorithms: ['HS256'] })"                      => "authenticated",
    "legacyJwt({ secret, algorithms: ['RS256'], credentialsRequired: true })" => "authenticated",
    "expressjwt({ secret: 's', credentialsRequired: false })"                 => "passes",
    "expressjwt({ secret: 's', credentialsRequired: optional })"              => "(authenticated | unresolved:credentialsRequired: optional)",
    "expressjwt({ secret, credentialsRequired })"                             => "(authenticated | unresolved:credentialsRequired: credentialsRequired)",
    "expressjwt({ secret: 's', onExpired: refresh })"                         => nil,
    "expressjwt({ ...base })"                                                 => nil,
    "expressjwt({ [key]: 's' })"                                              => nil,
    "expressjwt(options)"                                                     => nil,
    "expressjwt({ secret: 's' }).unless({ path: ['/login'] })"                => "(authenticated | unresolved:.unless({ path: ['/login'] }))",
    "expressjwt({ secret: 's' }).unless({ path: ['/login'] }).other()"        => nil,
    # express-basic-auth, connect-ensure-login, express-openid-connect.
    "basicAuth({ users: { admin: 'x' }, challenge: true })"  => "authenticated",
    "basicAuth({ authorizer: check, authorizeAsync: true })" => "authenticated",
    "basicAuth"                                              => nil,
    "ensureLoggedIn()"                                       => "authenticated",
    "ensureLoggedIn('/login')"                               => "authenticated",
    "ensure.ensureLoggedIn()"                                => "authenticated",
    "ensureLoggedOut('/')"                                   => "unresolved:ensureLoggedOut('/')",
    "requiresAuth()"                                         => "authenticated",
    "requiresAuth((req) => !req.oidc.isAuthenticated())"     => "unresolved:requiresAuth((req) => !req.oidc.isAuthenticated())",
    # express-oauth2-jwt-bearer: a token, then every scope, any scope, a claim.
    "auth()"                                       => "authenticated",
    "auth({ audience: 'x', authRequired: false })" => "passes",
    "auth({ authRequired: flag })"                 => "(authenticated | unresolved:authRequired: flag)",
    "auth({ authRequired })"                       => "(authenticated | unresolved:authRequired: authRequired)",
    "auth({ validators: { role: 'admin' } })"      => "authenticated & unresolved:auth({ validators: { role: 'admin' } })",
    "auth({ ...config })"                          => "authenticated & unresolved:auth({ ...config })",
    "requiredScopes('read:a write:b')"             => "authenticated & scope:read:a & scope:write:b",
    "requiredScopes(['read:a', SCOPE])"            => "authenticated & scope:read:a & unresolved:SCOPE",
    "requiredScopes(['read a'])"                   => "authenticated & unresolved:'read a'",
    "requiredScopes(`read:${x}`)"                  => "authenticated & unresolved:requiredScopes(`read:${x}`)",
    "requiredScopes('')"                           => "authenticated & unresolved:requiredScopes('')",
    "requiredScopes('a  b')"                       => "authenticated & unresolved:requiredScopes('a  b')",
    "requiredScopes('a\\tb')"                      => "authenticated & unresolved:requiredScopes('a\\tb')",
    "scopeIncludesAny('read:a read:b')"            => "authenticated & (scope:read:a | scope:read:b)",
    "claimEquals('role', 'admin')"                 => "authenticated & unresolved:claimEquals('role', 'admin')",
    # express-jwt-authz: a user, then any scope, or every with checkAllScopes.
    "jwtAuthz(['a', 'b'])"                               => "authenticated & (scope:a | scope:b)",
    "jwtAuthz(['a', 'b'], { checkAllScopes: true })"     => "authenticated & scope:a & scope:b",
    "jwtAuthz(['a'], { failWithError: true })"           => "authenticated & scope:a",
    "jwtAuthz(['a'], { customScopeKey: 'permissions' })" => "authenticated & unresolved:jwtAuthz(['a'], { customScopeKey: 'permissions' })",
    "jwtAuthz(['a'], { checkAllScopes: all })"           => "authenticated & unresolved:jwtAuthz(['a'], { checkAllScopes: all })",
    "jwtAuthz(['a', 'b'], { checkAllScopes })"           => "authenticated & unresolved:jwtAuthz(['a', 'b'], { checkAllScopes })",
    "jwtAuthz([])"                                       => "authenticated & unresolved:jwtAuthz([])",
    # hono/*.
    "jwt({ secret: 'my-secret' })"                => "authenticated",
    "bearerAuth({ token: 'secret-token' })"       => "authenticated",
    "honoBasic({ username: 'a', password: 'b' })" => "authenticated",
    # Packages that refuse nobody for who they are.
    "cors()"            => "passes",
    "bodyParser.json()" => "passes",
    "express.json()"    => "passes",
    "express.Router()"  => nil,
    # Not a known package's middleware.
    "local()"                => nil,
    "requireAuth()"          => nil,
    "myJwt({ secret: 's' })" => nil,
  }.each do |text, expected|
    it "reads #{text}" do
      reading(text).should eq(expected)
    end
  end

  it "keeps a guard it cannot read as signed in plus the unread check" do
    JsMiddlewareAccess.fallback("requireAuth").should eq([[Access::Atom.new(:authenticated)], [Access::Atom.new(:unresolved, "requireAuth")]])
  end

  it "reads a strategy name the app registers as another strategy as unread" do
    call = JsMiddlewareAccess.parse("passport.authenticate('bearer')", imports).not_nil!
    JsMiddlewareAccess.read(call, Set{"bearer"}).should be_nil
  end

  it "lets a name the module declares, or a commented-out import, bind no package" do
    code = "// import { bearerAuth } from 'hono/bearer-auth'\nconst bearerAuth = () => 1\nconst passport = require('passport')\n"
    found = JsMiddlewareAccess.package_imports({"bearerAuth" => {"hono/bearer-auth", "bearerAuth"}, "passport" => {"passport", nil}}, code)
    found.keys.should eq(["passport"])
  end

  {
    # Always hands the request on.
    {"function stamp(req, res, next) { req.at = Date.now(); next(); }", :express}               => true,
    {"(req, res, next) => { if (req.user) req.role = req.user.role; return next() }", :express} => true,
    {"async (c, next) => { c.set('at', Date.now()); await next() }", :hono}                     => true,
    # May answer, refuse, or not hand on.
    {"(req, res, next) => { if (!req.user.admin) return res.sendStatus(403); next() }", :express}    => false,
    {"(req, res, next) => { if (!req.user) throw new Error('x'); next() }", :express}                => false,
    {"(req, res, next) => { if (!req.user) return next(new Error('x')); next() }", :express}         => false,
    {"(req, res, next) => { if (!req.user) return; next() }", :express}                              => false,
    {"(req, res, next) => { check(req, next) }", :express}                                           => false,
    {"(req, res) => { res.json({}) }", :express}                                                     => false,
    {"async (c, next) => { if (!c.req.header('x')) return c.text('no', 403); await next() }", :hono} => false,
    {"async (c, next) => { c.res = new Response('x'); await next() }", :hono}                        => false,
    {"createMiddleware(async (c, next) => { await next() })", :hono}                                 => nil,
    {"requireRole('admin')", :express}                                                               => nil,
  }.each do |(text, kind), expected|
    it "reads whether #{text} always hands the request on" do
      found = JsMiddlewareAccess.function_parts(text)
      if expected.nil?
        found.should be_nil
      else
        params, body = found.not_nil!
        (kind == :express ? JsMiddlewareAccess.express_passes?(params, body) : JsMiddlewareAccess.hono_passes?(params, body)).should eq(expected)
      end
    end
  end
end
