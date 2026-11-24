require "../../../models/access"
require "../../../utils/top_level_split"
require "../../../utils/js_literal_scanner"
require "../../../utils/c_comments"

# Reads what a middleware asks of a caller: a call of a known package,
# judged from the call as written and the package its callee is imported
# from, or a function body that provably always hands the request on. Each
# package rule follows the package's own source:
#
# - passport `lib/middleware/authenticate.js`: an array of strategies stops
#   at the first that succeeds and fails only when all fail; a strategy that
#   calls `pass()` (`session` in `lib/strategies/session.js` with no user in
#   the session, passport-anonymous always) hands the request on without a
#   user; a callback argument decides the outcome itself. Which strategy a
#   name stands for is what the app registers under it.
# - express-jwt `src/index.ts`: no token is a 401 unless `credentialsRequired`
#   is false; `.unless(...)` (express-unless) skips the check for what it lists.
# - express-basic-auth `index.js`: a request without credentials, or with ones
#   the authorizer refuses, is a 401 whatever the options.
# - connect-ensure-login: `ensureLoggedIn` redirects a caller for whom
#   `req.isAuthenticated()` is false; `ensureLoggedOut` lets only those in.
# - express-oauth2-jwt-bearer `access-token-jwt/src/claim-check.ts`: every
#   claim check (`requiredScopes`, `scopeIncludesAny`, `claim*`) throws
#   Unauthorized without a token payload; `requiredScopes` needs every scope
#   (a string is split on single spaces), `scopeIncludesAny` one of them;
#   `auth({ authRequired: false })` lets a request without a token through.
# - express-jwt-authz `lib/index.js`: refuses without `req.user`; any one
#   scope, every scope with `checkAllScopes: true`.
# - express-openid-connect `middleware/requiresAuth.js`: `requiresAuth()` and
#   the claim checks send a signed-out caller to log in; a custom check
#   function decides itself.
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

  # An object literal's members, by key; nil for a shorthand member
  # (`{ checkAllScopes }`), whose value is a binding, not a literal.
  alias Options = Hash(String, String?)

  AUTHENTICATED = [[Access::Atom.new(Access::Kind::Authenticated)]]
  # Never refuses: contributes nothing.
  PASSES = Access::CNF.new

  LITERAL = /\A\s*(?:'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)"|`([^`$\\]*)`)\s*\z/
  HEAD    = /\A([A-Za-z_$][\w$]*)((?:\s*\.\s*[A-Za-z_$][\w$]*)*)\s*/
  # Strategies that refuse a caller without the credential they read.
  PASSPORT_REFUSING = Set{"jwt", "bearer", "basic", "digest", "local"}
  # Strategies that call `pass()`: the request goes on with no user.
  PASSPORT_PASSING = Set{"anonymous", "session"}
  # Packages whose strategies refuse a caller without their credential.
  PASSPORT_REFUSING_PACKAGES = Set{"passport-jwt", "passport-local", "passport-http", "passport-http-bearer"}
  # passport options decide where a refused caller goes, not whether one is.
  PASSPORT_KEYS = Set{"session", "failureRedirect", "failureFlash", "failureMessage", "failWithError", "successRedirect", "successFlash", "successMessage", "successReturnToOrRedirect", "assignProperty", "authInfo", "keepSessionInfo", "scope", "state", "prompt"}
  # express-jwt options that change what is verified, not whether a token
  # is required. Any other key (`onExpired` lets an expired token through)
  # is not read.
  EXPRESS_JWT_KEYS = Set{"secret", "algorithms", "audience", "issuer", "requestProperty", "getToken", "isRevoked", "credentialsRequired", "complete", "maxAge", "subject", "jwtid", "clockTolerance", "ignoreExpiration", "ignoreNotBefore"}
  # express-oauth2-jwt-bearer options that only say how a token is
  # verified. `validators` adds checks of its own.
  OAUTH2_KEYS = Set{"audience", "issuerBaseURL", "issuer", "jwksUri", "secret", "tokenSigningAlg", "timeoutDuration", "cacheMaxAge", "agent", "clockTolerance", "maxTokenAge", "strict", "authRequired"}
  UNLESS_TAIL = /\A\.\s*unless\s*\(/
  # Packages that never refuse a caller for who it is: headers, logging,
  # parsing, compression, sessions, input validation.
  NON_GUARD_PACKAGES = Set{"cors", "body-parser", "helmet", "morgan", "compression", "cookie-parser", "multer", "express-session", "serve-static",
                           "hono/cors", "hono/logger", "hono/etag", "hono/secure-headers", "hono/compress", "hono/pretty-json", "hono/timing", "hono/request-id", "@hono/zod-validator", "hono/validator"}
  NON_GUARD_EXPORTS = Set{ {"express", "json"}, {"express", "urlencoded"}, {"express", "static"}, {"express", "text"}, {"express", "raw"},
                          {"passport", "initialize"}, {"passport", "session"} }
  # A scope token as the packages split it: no whitespace, no quote or
  # backslash (an escape is not decoded here).
  SCOPE_TOKEN = /\A[^\s"'`\\]+\z/

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

  # The import bindings of `code` (comments stripped) that are not shadowed
  # by a declaration of the same name in it.
  def package_imports(imports : Imports, code : String) : Imports
    imports.reject do |name, _|
      code.matches?(/(?<![\w$.])(?:(?:const|let|var)\s+#{Regex.escape(name)}(?![\w$])(?!\s*=\s*require\s*\()|function\s*\*?\s*#{Regex.escape(name)}(?![\w$])|class\s+#{Regex.escape(name)}(?![\w$]))/)
    end
  end

  # What the call requires; `PASSES` for a middleware that never refuses a
  # caller; nil when it is not a middleware this module reads. `unrefusing`
  # names the Passport strategies the app registers as something other
  # than a known refusing strategy.
  def read(call : Call, unrefusing : Set(String) = Set(String).new) : Access::CNF?
    return PASSES if NON_GUARD_PACKAGES.includes?(call.package) || NON_GUARD_EXPORTS.includes?({call.package, call.export})
    return express_jwt(call) if call.package == "express-jwt" && call.export.in?(nil, "expressjwt")
    return unless call.tail.empty?
    args = call.args || return
    case {call.package, call.export}
    when {"passport", "authenticate"}
      passport(call, args, unrefusing)
    when {"express-basic-auth", nil},
         {"connect-ensure-login", "ensureLoggedIn"},
         {"hono/jwt", "jwt"},
         {"hono/bearer-auth", "bearerAuth"},
         {"hono/basic-auth", "basicAuth"}
      AUTHENTICATED
    when {"connect-ensure-login", "ensureLoggedOut"}
      unresolved(call.text)
    when {"express-oauth2-jwt-bearer", "auth"}
      oauth2_auth(call, args)
    when {"express-oauth2-jwt-bearer", "requiredScopes"}
      AUTHENTICATED + scopes(args, call.text, all: true)
    when {"express-oauth2-jwt-bearer", "scopeIncludesAny"}
      AUTHENTICATED + scopes(args, call.text, all: false)
    when {"express-oauth2-jwt-bearer", "claimEquals"},
         {"express-oauth2-jwt-bearer", "claimIncludes"},
         {"express-oauth2-jwt-bearer", "claimCheck"},
         {"express-openid-connect", "claimEquals"},
         {"express-openid-connect", "claimIncludes"},
         {"express-openid-connect", "claimCheck"}
      fallback(call.text)
    when {"express-jwt-authz", nil}
      jwt_authz(call, args)
    when {"express-openid-connect", "requiresAuth"}
      args.blank? ? AUTHENTICATED : unresolved(call.text)
    end
  end

  # A guard noir found but whose check it did not read: it refuses an
  # anonymous caller, and asks something more it could not name.
  def fallback(text : String) : Access::CNF
    AUTHENTICATED + unresolved(text)
  end

  def unresolved(text : String) : Access::CNF
    [[Access::Atom.new(Access::Kind::Unresolved, text)]]
  end

  # A function's parameter names and its body, when `text` is one function
  # (`function f(req, res, next) { … }`, `async (c, next) => { … }`, or a
  # declaration bound to one); nil for anything else, a factory call
  # wrapping one included. Without `whole`, text may follow the function.
  FUNCTION_HEAD = /\A\s*(?:export\s+)?(?:default\s+)?(?:(?:const|let|var)\s+[A-Za-z_$][\w$]*\s*(?::[^=]+)?=\s*)?(?:async\s+)?(?:function\b\s*\*?\s*[A-Za-z_$]*\s*)?\z/

  def function_parts(text : String, whole : Bool = true) : {Array(String), String}?
    code = Noir::JSLiteralScanner.blank_literals(Noir::CComments.strip(text, quotes: %("'`)))
    open = code.index('(') || return
    return unless code[0...open].matches?(FUNCTION_HEAD)
    close = Noir::JSLiteralScanner.find_matching_paren(code, open) || return
    rest = code[close + 1..]
    arrow = rest.match(/\A\s*(?::[^={]+)?(=>)?\s*\{/) || return
    return if arrow[1]?.nil? && !code[0...open].matches?(/\bfunction\b/)
    brace = close + 1 + arrow.end(0) - 1
    body_end = Noir::JSLiteralScanner.find_matching_brace(code, brace) || return
    return if whole && !code[body_end + 1..].strip.matches?(/\A[;)]*\z/)
    params = Noir::TopLevelSplit.split(code[open + 1...close], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).map { |param| param.strip.match(/\A[A-Za-z_$][\w$]*/).try(&.[0]) || "" }
    {params.reject(&.empty?), code[brace + 1...body_end]}
  end

  # Whether an Express middleware `(req, res, next)` always calls `next()`:
  # it never touches the response, throws, hands `next` an error, or
  # returns other than through `next()`.
  def express_passes?(params : Array(String), body : String) : Bool
    return false unless params.size == 3
    response = Regex.escape(params[1])
    return false if body.matches?(/(?<![\w$.])#{response}(?![\w$])/)
    passes_on?(body, params[2])
  end

  # The same for a Hono middleware `(c, next)`: it only reads the request
  # or context values, never answers (`c.text(…)`, `new Response`), throws,
  # or returns other than through `next()`.
  def hono_passes?(params : Array(String), body : String) : Bool
    return false unless params.size == 2
    context = Regex.escape(params[0])
    mentions = body.scan(/(?<![\w$.])#{context}(?![\w$])/).size
    reads = body.scan(/(?<![\w$.])#{context}\s*\.\s*(?:req|get|set|var|env)\b(?!\s*=[^=])/).size
    return false if mentions != reads || body.matches?(/\bnew\s+Response\b/)
    passes_on?(body, params[1])
  end

  private def passes_on?(body : String, next_name : String) : Bool
    name = Regex.escape(next_name)
    return false if body.matches?(/\bthrow\b/)
    calls = body.scan(/(?<![\w$.])#{name}\s*\(\s*\)/).size
    return false if calls == 0 || body.scan(/(?<![\w$.])#{name}(?![\w$])/).size != calls
    body.scan(/\breturn\b/).all? { |at| body[at.end(0)..].matches?(/\A\s*(?:await\s+)?#{name}\s*\(\s*\)/) }
  end

  private def parts(args : String) : Array(String)
    Noir::TopLevelSplit.split(args, ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).map(&.strip).reject(&.empty?)
  end

  private def literal(text : String) : String?
    match = text.match(LITERAL) || return
    match[1]? || match[2]? || match[3]?
  end

  # The members of an object literal, or nil when `text` is not one or a
  # member is spread, computed or a method.
  private def options(text : String) : Options?
    text = text.strip
    return unless text.starts_with?('{') && text.ends_with?('}')
    found = Options.new
    parts(text[1...-1]).each do |entry|
      if member = entry.match(/\A['"]?([A-Za-z_$][\w$]*)['"]?\s*:(.*)\z/m)
        found[member[1]] = member[2].strip
      elsif entry.matches?(/\A[A-Za-z_$][\w$]*\z/)
        found[entry] = nil
      else
        return
      end
    end
    found
  end

  private def passport(call : Call, args : String, unrefusing : Set(String)) : Access::CNF?
    list = parts(args)
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
    return unless extra.all? { |arg| options(arg).try(&.keys.all? { |key| PASSPORT_KEYS.includes?(key) }) }
    return unresolved(call.text) if names.any? { |strategy| PASSPORT_PASSING.includes?(strategy) }
    AUTHENTICATED if names.all? { |strategy| PASSPORT_REFUSING.includes?(strategy) && !unrefusing.includes?(strategy) }
  end

  private def express_jwt(call : Call) : Access::CNF?
    args = parts(call.args || return)
    return unless args.size == 1
    members = options(args[0]) || return
    return unless members.keys.all? { |key| EXPRESS_JWT_KEYS.includes?(key) }
    cnf = case required = members.fetch("credentialsRequired", "true")
          when "true"  then AUTHENTICATED
          when "false" then return PASSES
          else              [[Access::Atom.new(Access::Kind::Authenticated), Access::Atom.new(Access::Kind::Unresolved, "credentialsRequired: #{required || "credentialsRequired"}")]]
          end
    return cnf if call.tail.empty?
    return unless (unless_call = call.tail.match(UNLESS_TAIL)) && Noir::JSLiteralScanner.find_matching_paren(call.tail, unless_call.end(0) - 1) == call.tail.size - 1
    # express-unless skips the check for the requests it lists; which ones
    # is not read against this route.
    cnf.map { |clause| clause + [Access::Atom.new(Access::Kind::Unresolved, call.tail)] }
  end

  private def oauth2_auth(call : Call, args : String) : Access::CNF
    list = parts(args)
    return AUTHENTICATED if list.empty?
    members = list.size == 1 ? options(list[0]) : nil
    return fallback(call.text) unless members && members.keys.all? { |key| OAUTH2_KEYS.includes?(key) }
    case required = members.fetch("authRequired", "true")
    when "true"  then AUTHENTICATED
    when "false" then PASSES
    else              [[Access::Atom.new(Access::Kind::Authenticated), Access::Atom.new(Access::Kind::Unresolved, "authRequired: #{required || "authRequired"}")]]
    end
  end

  # `'read:a write:b'` or `['read:a', 'write:b']`: every scope with `all`,
  # one of them without. An unread element stays unresolved.
  private def scopes(args : String, text : String, all : Bool) : Access::CNF
    list = parts(args)
    return unresolved(text) unless list.size == 1
    atoms = if value = literal(list[0])
              tokens = value.split(' ')
              return unresolved(text) unless tokens.all?(&.matches?(SCOPE_TOKEN))
              tokens.map { |scope| Access::Atom.new(Access::Kind::Scope, scope) }
            elsif list[0].starts_with?('[') && list[0].ends_with?(']')
              parts(list[0][1...-1]).map do |element|
                (scope = literal(element)) && scope.matches?(SCOPE_TOKEN) ? Access::Atom.new(Access::Kind::Scope, scope) : Access::Atom.new(Access::Kind::Unresolved, element)
              end
            else
              [] of Access::Atom
            end
    return unresolved(text) if atoms.empty?
    all ? atoms.map { |atom| [atom] } : [atoms]
  end

  private def jwt_authz(call : Call, args : String) : Access::CNF
    list = parts(args)
    return fallback(call.text) unless list.size.in?(1, 2) && list[0].starts_with?('[')
    all = false
    if second = list[1]?
      members = options(second) || return fallback(call.text)
      return fallback(call.text) unless members.keys.all?(&.in?("checkAllScopes", "failWithError"))
      case members.fetch("checkAllScopes", "false")
      when "true"  then all = true
      when "false" then all = false
      else              return fallback(call.text)
      end
    end
    AUTHENTICATED + scopes(list[0], call.text, all)
  end
end
