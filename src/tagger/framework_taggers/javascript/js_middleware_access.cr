require "../../../models/access"
require "../../../utils/top_level_split"
require "../../../utils/js_literal_scanner"
require "../../../utils/c_comments"
require "./js_object_literal"

# Reads what a middleware from a known package asks of a caller, from the
# call as written and the package its callee is imported from. Each rule
# follows the package's own source:
#
# - passport `lib/middleware/authenticate.js`: an array of strategies stops
#   at the first that succeeds and fails only when all fail; a strategy that
#   calls `pass()` (`session` in `lib/strategies/session.js` with no user in
#   the session, passport-anonymous always) hands the request on without a
#   user; a callback argument decides the outcome itself.
# - express-jwt `src/index.ts`: no token is a 401 unless `credentialsRequired`
#   is false; `.unless(...)` (express-unless) skips the check for what it lists.
# - express-basic-auth `index.js`: a request without credentials, or with ones
#   the authorizer refuses, is a 401 whatever the options.
# - connect-ensure-login: `ensureLoggedIn` redirects a caller for whom
#   `req.isAuthenticated()` is false; `ensureLoggedOut` lets only those in.
# - express-oauth2-jwt-bearer `access-token-jwt/src/claim-check.ts`:
#   `requiredScopes` needs every scope (a string is split on spaces),
#   `scopeIncludesAny` one of them; `auth({ authRequired: false })` lets a
#   request without a token through.
# - express-jwt-authz `lib/index.js`: any one scope, every scope with
#   `checkAllScopes: true`.
# - express-openid-connect `middleware/requiresAuth.js`: `requiresAuth()`
#   sends a signed-out caller to log in; a custom check function decides
#   itself.
# - hono `jwt`, `bearerAuth`, `basicAuth`: an HTTPException 401 without a
#   valid credential.
module JsMiddlewareAccess
  extend self

  # A middleware as written: the package its callee is imported from, the
  # export it names (nil for the module's default), the text inside the
  # call's parentheses (nil when only referenced), what follows the call,
  # and the whole text.
  record Call, package : String, export : String?, args : String?, tail : String, text : String

  alias Imports = Hash(String, Tuple(String, String?))

  AUTHENTICATED = [[Access::Atom.new(Access::Kind::Authenticated)]]
  LITERAL       = /\A\s*(?:'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)"|`([^`$\\]*)`)\s*\z/
  HEAD          = /\A([A-Za-z_$][\w$]*)((?:\s*\.\s*[A-Za-z_$][\w$]*)*)\s*/
  # Strategies that refuse a caller without the credential they read.
  PASSPORT_REFUSING = Set{"jwt", "bearer", "basic", "digest", "local"}
  # Strategies that call `pass()`: the request goes on with no user.
  PASSPORT_PASSING = Set{"anonymous", "session"}
  # express-jwt options that change what is verified, not whether a token
  # is required. Any other key (`onExpired` lets an expired token through)
  # is left to the default reading.
  EXPRESS_JWT_KEYS = Set{"secret", "algorithms", "audience", "issuer", "requestProperty", "getToken", "isRevoked", "credentialsRequired", "complete", "maxAge", "subject", "jwtid", "clockTolerance", "ignoreExpiration", "ignoreNotBefore"}
  UNLESS_TAIL      = /\A\.\s*unless\s*\(/

  # `text` as a call of an imported package export, or nil.
  def parse(text : String, imports : Imports) : Call?
    code = Noir::CComments.strip(text, quotes: %("'`)).strip
    head = code.match(HEAD) || return
    binding = imports[head[1]]? || return
    members = head[2].split('.').map(&.strip).reject(&.empty?)
    specifier, exported = binding
    export = if members.empty?
               exported
             elsif exported.nil? && members.size == 1
               members[0]
             else
               return
             end
    rest = code[head.end(0)..]
    args = nil.as(String?)
    if rest.starts_with?('(')
      close = Noir::JSLiteralScanner.find_matching_paren(rest, 0) || return
      args = rest[1...close]
      rest = rest[close + 1..]
    end
    Call.new(specifier, export, args, rest.strip, code)
  end

  # What the call requires, or nil when it is not a middleware this module
  # reads (the caller then keeps its default reading).
  def read(call : Call) : Access::CNF?
    return express_jwt(call) if call.package == "express-jwt" && call.export.in?(nil, "expressjwt")
    return unless call.tail.empty?
    args = call.args
    case {call.package, call.export}
    when {"passport", "authenticate"}
      passport(call) if args
    when {"express-basic-auth", nil},
         {"connect-ensure-login", "ensureLoggedIn"},
         {"hono/jwt", "jwt"},
         {"hono/bearer-auth", "bearerAuth"},
         {"hono/basic-auth", "basicAuth"}
      AUTHENTICATED if args
    when {"connect-ensure-login", "ensureLoggedOut"}
      unresolved(call.text) if args
    when {"express-oauth2-jwt-bearer", "auth"}
      oauth2_auth(call) if args
    when {"express-oauth2-jwt-bearer", "requiredScopes"}
      scopes(args, call.text, all: true) if args
    when {"express-oauth2-jwt-bearer", "scopeIncludesAny"}
      scopes(args, call.text, all: false) if args
    when {"express-oauth2-jwt-bearer", "claimEquals"},
         {"express-oauth2-jwt-bearer", "claimIncludes"},
         {"express-oauth2-jwt-bearer", "claimCheck"},
         {"express-openid-connect", "claimEquals"},
         {"express-openid-connect", "claimIncludes"},
         {"express-openid-connect", "claimCheck"}
      unresolved(call.text) if args
    when {"express-jwt-authz", nil}
      jwt_authz(call) if args
    when {"express-openid-connect", "requiresAuth"}
      return unless args
      args.blank? ? AUTHENTICATED : unresolved(call.text)
    end
  end

  # A guard noir found but whose check it did not read: it refuses an
  # anonymous caller, and asks something more it could not name.
  def fallback(text : String) : Access::CNF
    [[Access::Atom.new(Access::Kind::Authenticated)], [Access::Atom.new(Access::Kind::Unresolved, text)]]
  end

  private def unresolved(text : String) : Access::CNF
    [[Access::Atom.new(Access::Kind::Unresolved, text)]]
  end

  private def parts(args : String) : Array(String)
    Noir::TopLevelSplit.split(args, ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).map(&.strip).reject(&.empty?)
  end

  private def literal(text : String) : String?
    match = text.match(LITERAL) || return
    match[1]? || match[2]? || match[3]?
  end

  private def object?(text : String) : Bool
    text.starts_with?('{') && text.ends_with?('}') && !text.includes?("...")
  end

  # The keys of an object literal, or nil when one is computed or spread.
  private def keys(object : String) : Array(String)?
    parts(object[1...-1]).map do |entry|
      entry.match(/\A['"]?([A-Za-z_$][\w$]*)['"]?\s*(?::|\z)/).try(&.[1]) || return
    end
  end

  private def passport(call : Call) : Access::CNF?
    list = parts(call.args || return)
    first = list.first? || return
    names = if name = literal(first)
              [name]
            elsif first.starts_with?('[') && first.ends_with?(']')
              parts(first[1...-1]).map { |element| literal(element) || return }
            end
    return if names.nil? || names.empty?
    extra = list[1..]
    return unresolved(call.text) if extra.any?(&.matches?(/\A(?:async\s+)?(?:function\b|\([^)]*\)\s*=>|[A-Za-z_$][\w$]*\s*=>)/))
    # A named options object or callback: which one is not read.
    return unless extra.all? { |arg| object?(arg) }
    return unresolved(call.text) if names.any? { |strategy| PASSPORT_PASSING.includes?(strategy) }
    AUTHENTICATED if names.all? { |strategy| PASSPORT_REFUSING.includes?(strategy) }
  end

  private def express_jwt(call : Call) : Access::CNF?
    args = parts(call.args || return)
    return unless args.size == 1 && object?(args[0])
    options = args[0]
    keys = keys(options) || return
    return unless keys.all? { |key| EXPRESS_JWT_KEYS.includes?(key) }
    required = keys.includes?("credentialsRequired") ? Noir::JSObjectLiteral.property(options, "credentialsRequired") : "true"
    return if required == "false"
    cnf = required == "true" ? AUTHENTICATED : [[Access::Atom.new(Access::Kind::Authenticated), Access::Atom.new(Access::Kind::Unresolved, "credentialsRequired: #{required}")]]
    return cnf if call.tail.empty?
    return unless (unless_call = call.tail.match(UNLESS_TAIL)) && Noir::JSLiteralScanner.find_matching_paren(call.tail, unless_call.end(0) - 1) == call.tail.size - 1
    # express-unless skips the check for the requests it lists; which ones
    # is not read against this route.
    cnf.map { |clause| clause + [Access::Atom.new(Access::Kind::Unresolved, call.tail)] }
  end

  private def oauth2_auth(call : Call) : Access::CNF?
    args = parts(call.args || return)
    return AUTHENTICATED if args.empty?
    return unless args.size == 1 && object?(args[0])
    required = Noir::JSObjectLiteral.property(args[0], "authRequired")
    return AUTHENTICATED if required.nil? || required == "true"
    return if required == "false"
    [[Access::Atom.new(Access::Kind::Authenticated), Access::Atom.new(Access::Kind::Unresolved, "authRequired: #{required}")]]
  end

  # `'read:a write:b'` or `['read:a', 'write:b']`: every scope with `all`,
  # one of them without. An unread element stays unresolved.
  private def scopes(args : String, text : String, all : Bool) : Access::CNF
    list = parts(args)
    return unresolved(text) unless list.size == 1
    atoms = if value = literal(list[0])
              value.split.map { |scope| Access::Atom.new(Access::Kind::Scope, scope) }
            elsif list[0].starts_with?('[') && list[0].ends_with?(']')
              parts(list[0][1...-1]).map do |element|
                (scope = literal(element)) && !scope.blank? ? Access::Atom.new(Access::Kind::Scope, scope) : Access::Atom.new(Access::Kind::Unresolved, element)
              end
            else
              [] of Access::Atom
            end
    return unresolved(text) if atoms.empty?
    all ? atoms.map { |atom| [atom] } : [atoms]
  end

  private def jwt_authz(call : Call) : Access::CNF
    args = parts(call.args || "")
    return unresolved(call.text) unless args.size.in?(1, 2) && args[0].starts_with?('[')
    all = false
    if options = args[1]?
      return unresolved(call.text) unless object?(options)
      keys = keys(options) || return unresolved(call.text)
      return unresolved(call.text) unless keys.all?(&.in?("checkAllScopes", "failWithError"))
      setting = Noir::JSObjectLiteral.property(options, "checkAllScopes")
      return unresolved(call.text) unless setting.in?(nil, "true", "false")
      all = setting == "true"
    end
    scopes(args[0], call.text, all)
  end
end
