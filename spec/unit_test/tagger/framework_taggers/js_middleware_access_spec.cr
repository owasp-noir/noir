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
  }
end

private def atom_text(atom : Access::Atom) : String
  atom.kind.unresolved? ? "unresolved:#{atom.value}" : atom.to_s
end

private def reading(text : String) : String?
  call = JsMiddlewareAccess.parse(text, imports) || return
  JsMiddlewareAccess.read(call).try do |cnf|
    cnf.map { |clause| atoms = clause.map { |atom| atom_text(atom) }.sort!; atoms.size > 1 ? "(#{atoms.join(" | ")})" : atoms[0] }.join(" & ")
  end
end

describe JsMiddlewareAccess do
  {
    # passport: one strategy, a chain of them, the passing ones, a callback.
    "passport.authenticate('jwt', { session: false })"                => "authenticated",
    "passport.authenticate(\"bearer\")"                               => "authenticated",
    "passport.authenticate(['jwt', 'basic'], { session: false })"     => "authenticated",
    "passport.authenticate(['jwt', 'anonymous'], { session: false })" => "unresolved:passport.authenticate(['jwt', 'anonymous'], { session: false })",
    "passport.authenticate('session')"                                => "unresolved:passport.authenticate('session')",
    "passport.authenticate('jwt', (err, user) => next())"             => "unresolved:passport.authenticate('jwt', (err, user) => next())",
    "passport.authenticate('jwt', function (err, user) {})"           => "unresolved:passport.authenticate('jwt', function (err, user) {})",
    "passport.authenticate('jwt', options)"                           => nil,
    "passport.authenticate('saml-admin')"                             => nil,
    "passport.authenticate(strategy)"                                 => nil,
    "passport.authenticate(['jwt', name])"                            => nil,
    "passport.authenticate('jwt')(req, res, next)"                    => nil,
    "passport.session()"                                              => nil,
    # express-jwt: required by default, optional, unread options, `.unless`.
    "expressjwt({ secret: 's', algorithms: ['HS256'] })"                      => "authenticated",
    "legacyJwt({ secret, algorithms: ['RS256'], credentialsRequired: true })" => "authenticated",
    "expressjwt({ secret: 's', credentialsRequired: false })"                 => nil,
    "expressjwt({ secret: 's', credentialsRequired: optional })"              => "(authenticated | unresolved:credentialsRequired: optional)",
    "expressjwt({ secret: 's', onExpired: refresh })"                         => nil,
    "expressjwt({ ...base })"                                                 => nil,
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
    # express-oauth2-jwt-bearer: every scope, any scope, claims, optional auth.
    "auth()"                                       => "authenticated",
    "auth({ audience: 'x', authRequired: false })" => nil,
    "auth({ authRequired: flag })"                 => "(authenticated | unresolved:authRequired: flag)",
    "requiredScopes('read:a write:b')"             => "scope:read:a & scope:write:b",
    "requiredScopes(['read:a', SCOPE])"            => "scope:read:a & unresolved:SCOPE",
    "requiredScopes(`read:${x}`)"                  => "unresolved:requiredScopes(`read:${x}`)",
    "requiredScopes('')"                           => "unresolved:requiredScopes('')",
    "scopeIncludesAny('read:a read:b')"            => "(scope:read:a | scope:read:b)",
    "claimEquals('role', 'admin')"                 => "unresolved:claimEquals('role', 'admin')",
    # express-jwt-authz: any by default, all with checkAllScopes.
    "jwtAuthz(['a', 'b'])"                               => "(scope:a | scope:b)",
    "jwtAuthz(['a', 'b'], { checkAllScopes: true })"     => "scope:a & scope:b",
    "jwtAuthz(['a'], { failWithError: true })"           => "scope:a",
    "jwtAuthz(['a'], { customScopeKey: 'permissions' })" => "unresolved:jwtAuthz(['a'], { customScopeKey: 'permissions' })",
    "jwtAuthz(['a'], { checkAllScopes: all })"           => "unresolved:jwtAuthz(['a'], { checkAllScopes: all })",
    "jwtAuthz([])"                                       => "unresolved:jwtAuthz([])",
    # hono/*.
    "jwt({ secret: 'my-secret' })"                => "authenticated",
    "bearerAuth({ token: 'secret-token' })"       => "authenticated",
    "honoBasic({ username: 'a', password: 'b' })" => "authenticated",
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
end
