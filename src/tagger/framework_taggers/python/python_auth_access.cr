require "../../../models/access"
require "../../../utils/top_level_split"
require "./django_access"

# Reads the access vocabulary of the Flask auth extensions (Flask-Login,
# Flask-JWT-Extended, Flask-Security, Flask-HTTPAuth, APIFairy,
# Flask-AppBuilder), Tornado and sanic-jwt into a requirement. Each reader
# takes a decorator's arguments as text; the caller has bound its name to
# the library.
module PythonAuthAccess
  extend self

  AUTHENTICATED = Access::Atom.new(:authenticated)
  LITERAL       = /\A\s*[rRuU]?(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')\s*\z/
  KEYWORD       = /\A([A-Za-z_]\w*)\s*=(?!=)\s*(.*)\z/m
  FALSY         = %w[False None]

  # The libraries whose decorators let an OPTIONS request through unchecked
  # (flask_login `EXEMPT_METHODS`, flask_jwt_extended `exempt_methods`,
  # Flask-HTTPAuth `if request.method != 'OPTIONS'`, sanic-jwt
  # `_do_protection`).
  OPTIONS_EXEMPT = %w[flask_login flask_jwt_extended flask_httpauth sanic_jwt]

  # The requirement of decorator `module.name` (`flask_login.login_required`,
  # `flask_security.decorators.roles_required`: the top package names it)
  # written with `args` (nil when not called) on a route answering
  # `method`; nil for a name this reader does not know. `login_disabled`:
  # the project sets flask_login's `LOGIN_DISABLED`, which turns its
  # decorators off (flask-login 0.6.3 `login_required`).
  def library_decorator(qualified : String, args : String?, source : String, method : String = "GET", login_disabled : Bool = false) : Access::CNF?
    qualified = "#{qualified.partition('.')[0]}.#{qualified.rpartition('.')[2]}"
    # Flask-Security re-exports flask_login's `login_required`.
    qualified = "flask_login.login_required" if qualified == "flask_security.login_required"
    package = qualified.rpartition('.')[0]
    return unresolved("#{source} (skipped for OPTIONS)") if method.upcase == "OPTIONS" && OPTIONS_EXEMPT.includes?(package)
    case qualified
    when "flask_login.login_required"
      login_disabled ? DjangoAccess.liftable(signed_in, "LOGIN_DISABLED") : signed_in
    when "flask_jwt_extended.jwt_required"       then jwt_required(args, source)
    when "flask_jwt_extended.fresh_jwt_required" then signed_in + unresolved(source)
    when "flask_jwt_extended.jwt_optional"       then unresolved(source)
    when "flask_jwt.jwt_required"                then signed_in
    when "flask_security.auth_required"          then auth_required(args, source)
    when "flask_security.http_auth_required"     then signed_in
    when "flask_security.roles_required"         then roles(args, source, every: true)
    when "flask_security.roles_accepted"         then roles(args, source, every: false)
    when "sanic_jwt.protected"                   then signed_in
    end
  end

  # flask-jwt-extended 4 `jwt_required(optional=False, fresh=False,
  # refresh=False, locations=None, verify_type=True,
  # skip_revocation_check=False)`. Version 3 took no arguments and was
  # applied bare; version 4 applied bare hands the view in as `optional`.
  JWT_PARAMS = %w[optional fresh refresh locations verify_type skip_revocation_check]

  def jwt_required(args : String?, source : String) : Access::CNF
    return signed_in + unresolved("#{source} (flask-jwt-extended 4 needs jwt_required())") if args.nil?
    values = keywords(args, JWT_PARAMS) || return unresolved(source)
    optional = values.delete("optional")
    return unresolved(source) if optional && !FALSY.includes?(optional)
    cnf = signed_in
    values.each do |key, value|
      next if key.in?("locations", "verify_type", "skip_revocation_check")
      # `fresh` and `refresh` ask for a kind of token noir has no atom for.
      cnf += unresolved(source) unless key.in?("fresh", "refresh") && FALSY.includes?(value)
    end
    cnf.uniq
  end

  # Flask-Security `auth_required(*auth_methods, within=-1, grace=None)`:
  # every mechanism authenticates; `within` adds a freshness check.
  def auth_required(args : String?, source : String) : Access::CNF
    return signed_in if args.nil?
    cnf = signed_in
    parts(args).each do |arg|
      if kw = arg.match(KEYWORD)
        next if kw[1] == "grace" || (kw[1] == "within" && kw[2].strip == "-1")
        cnf += unresolved(source)
      elsif arg.starts_with?("**")
        cnf += unresolved(source)
      end
    end
    cnf.uniq
  end

  # Flask-Security `roles_required(*roles)` needs every role (it refuses
  # at the first `Permission(RoleNeed(role))` the identity fails),
  # `roles_accepted(*roles)` any one. With no roles neither names a role,
  # which a guard never reads as open: it stays unresolved.
  def roles(args : String?, source : String, every : Bool) : Access::CNF
    items = args.try { |text| parts(text) } || [] of String
    return unresolved(source) if items.empty? || items.any? { |item| item.starts_with?('*') || item.matches?(KEYWORD) }
    atoms = items.map { |item| atom(:role, item) }
    every ? atoms.map { |found| [found] } : [atoms]
  end

  # Flask-HTTPAuth `login_required(role=None, optional=None)`, also what
  # APIFairy's `authenticate(auth, **kwargs)` applies. `optional=True`
  # admits a caller without credentials. `role` is any one of a list, and
  # all of a list nested in it (`HTTPAuth.authorize`); it is read only when
  # the decorator's object is known to be a Flask-HTTPAuth one.
  def httpauth(args : String?, source : String, httpauth : Bool, method : String = "GET") : Access::CNF
    return unresolved("#{source} (skipped for OPTIONS)") if method.upcase == "OPTIONS"
    return signed_in if args.nil?
    values = keywords(args, %w[f role optional]) || return unresolved(source)
    optional = values["optional"]?
    return unresolved(source) if optional && !FALSY.includes?(optional)
    role = values["role"]?
    return signed_in if role.nil? || role == "None"
    return signed_in + unresolved(source) unless httpauth
    elements(role).try { |items| either_roles(items) } || atom_cnf(:role, role)
  end

  private def either_roles(items : Array(String)) : Access::CNF?
    return if items.empty?
    items.map do |item|
      nested = elements(item)
      nested ? (nested.empty? ? unresolved(item) : nested.map { |inner| [atom(:role, inner)] }) : atom_cnf(:role, item)
    end.reduce { |left, right| Access.either(left, right) }
  end

  # sanic-jwt `scoped(scopes, require_all=True, require_all_actions=True,
  # initialized_on=None, **kw)` protects the route, then checks scopes:
  # every listed one by default, any one with `require_all=False`. A scope
  # with actions (`user:read`) is also held by a caller whose scope names
  # its namespace with no actions or more of them (`validate_single_scope`),
  # and a project can replace the check (`override_scope_validator`,
  # `destructure_scopes`): those stay unresolved beside the scope.
  def scoped(args : String?, source : String, custom_validator : Bool, method : String = "GET") : Access::CNF
    return unresolved("#{source} (skipped for OPTIONS)") if method.upcase == "OPTIONS"
    values = args.try { |text| keywords(text, %w[scopes require_all require_all_actions initialized_on]) }
    scopes = values.try(&.["scopes"]?) || return signed_in + unresolved(source)
    # `scopes` None or False skips the check, protection included.
    return unresolved(source) if FALSY.includes?(scopes)
    return signed_in + unresolved(source) if custom_validator
    items = elements(scopes) || [scopes]
    return signed_in + unresolved(source) if items.empty?
    atoms = items.map do |item|
      found = atom(:scope, item)
      found.kind.scope? && found.value.to_s.includes?(':') ? [found, Access::Atom.new(:unresolved, "#{source} (a broader scope also passes)")] : [found]
    end
    case values.try(&.["require_all"]?)
    when nil, "True" then signed_in + atoms
    when "False"     then signed_in + [atoms.flatten.uniq!]
    else                  signed_in + unresolved(source)
    end
  end

  # Flask-AppBuilder's `protect` / `has_access` / `has_access_api` pass a
  # caller whose roles hold `can_<permission> on <view>`, or anyone when
  # the Public role (AUTH_ROLE_PUBLIC) holds it. The view's
  # `method_permission_name` and `class_permission_name` can rename the
  # permission at run time, so its name stays text.
  def fab(permission : String, setting : String) : Access::CNF
    DjangoAccess.liftable(signed_in + unresolved(permission), setting)
  end

  # The flask-appbuilder permission text for `permission` on `view`.
  def fab_permission(permission : String, view : String) : String
    "flask-appbuilder permission can_#{permission} on #{view} (method_permission_name or class_permission_name may rename it)"
  end

  IMPORT_PARENS    = /(\bimport[ \t]*)\(([^)]*)\)/
  FROM_IMPORT_LINE = /^[ \t]*from[ \t]+([\w.]+)[ \t]+import[ \t]+([^\n]+)/m

  # What each name a `from x import y [as z]` in `source` binds: `z` =>
  # `"x.y"`. A later import of a name wins.
  def from_imports(source : String) : Hash(String, String)
    bindings = Hash(String, String).new
    source = source.gsub(IMPORT_PARENS) { "#{$1}#{$2.gsub(/#[^\n]*/, "").gsub(/\s+/, " ")}" }
    source.scan(FROM_IMPORT_LINE) do |m|
      m[2].sub(/#.*/, "").split(',').each do |item|
        name, _, bound = item.strip.partition(/\s+as\s+/)
        bindings[bound.empty? ? name : bound] = "#{m[1]}.#{name}" unless name.empty?
      end
    end
    bindings
  end

  def signed_in : Access::CNF
    [[AUTHENTICATED]]
  end

  def unresolved(fragment : String) : Access::CNF
    DjangoAccess.unresolved(fragment)
  end

  # A string literal's text, else nil.
  def literal(text : String) : String?
    found = text.match(LITERAL) || return
    (found[1]? || found[2]?).to_s.gsub(/\\(.)/, "\\1")
  end

  # The items of a list or tuple literal, else nil.
  def elements(text : String) : Array(String)?
    text = text.strip
    return unless (text.starts_with?('[') && text.ends_with?(']')) || (text.starts_with?('(') && text.ends_with?(')'))
    parts(text[1...-1])
  end

  private def atom(kind : Access::Kind, text : String) : Access::Atom
    (value = literal(text)) ? Access::Atom.new(kind, value) : Access::Atom.new(:unresolved, text.strip)
  end

  private def atom_cnf(kind : Access::Kind, text : String) : Access::CNF
    [[atom(kind, text)]]
  end

  # The arguments by parameter name, positional ones taking `params` in
  # order; nil when one cannot be placed (`*args`, too many positionals).
  private def keywords(args : String, params : Array(String)) : Hash(String, String)?
    values = Hash(String, String).new
    position = 0
    parts(args).each do |arg|
      return if arg.starts_with?('*')
      if kw = arg.match(KEYWORD)
        values[kw[1]] = kw[2].strip
      else
        name = params[position]? || return
        values[name] = arg
        position += 1
      end
    end
    values
  end

  private def parts(text : String) : Array(String)
    Noir::TopLevelSplit.split(text, ',', DjangoAccess::ARGS)
  end
end
