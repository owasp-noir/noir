require "../../../models/access"

# Reads what a Laravel middleware entry (`auth:sanctum`, `can:update,post`,
# `role:admin|editor,api`) or a gate call asks of the caller.
module LaravelAccess
  extend self

  # The built-in `auth` / `auth:sanctum` / `auth.basic` aliases.
  AUTH_ALIAS = /\Aauth(?:\.basic)?(?::|\z)/

  enum Params
    AnyRole
    AnyPermission
    AllScopes
    AnyScope
    Unread
  end

  # Package middleware whose parameter list says what it checks, by class.
  # Spatie moved `Middlewares\` to `Middleware\` in v6; Passport 13 renamed
  # `CheckScopes` / `CheckForAnyScope` to `CheckToken` / `CheckTokenForAnyScope`.
  PACKAGE_PARAMS = {
    "Spatie\\Permission\\Middleware\\RoleMiddleware"                         => Params::AnyRole,
    "Spatie\\Permission\\Middleware\\PermissionMiddleware"                   => Params::AnyPermission,
    "Spatie\\Permission\\Middleware\\RoleOrPermissionMiddleware"             => Params::Unread,
    "Laravel\\Sanctum\\Http\\Middleware\\CheckAbilities"                     => Params::AllScopes,
    "Laravel\\Sanctum\\Http\\Middleware\\CheckScopes"                        => Params::AllScopes,
    "Laravel\\Sanctum\\Http\\Middleware\\CheckForAnyAbility"                 => Params::AnyScope,
    "Laravel\\Sanctum\\Http\\Middleware\\CheckForAnyScope"                   => Params::AnyScope,
    "Laravel\\Passport\\Http\\Middleware\\CheckScopes"                       => Params::AllScopes,
    "Laravel\\Passport\\Http\\Middleware\\CheckToken"                        => Params::AllScopes,
    "Laravel\\Passport\\Http\\Middleware\\CheckClientCredentials"            => Params::AllScopes,
    "Laravel\\Passport\\Http\\Middleware\\CheckForAnyScope"                  => Params::AnyScope,
    "Laravel\\Passport\\Http\\Middleware\\CheckTokenForAnyScope"             => Params::AnyScope,
    "Laravel\\Passport\\Http\\Middleware\\CheckClientCredentialsForAnyScope" => Params::AnyScope,
  }

  # The aliases these packages tell apps to register. Which class one names
  # is up to the app, so without its alias table the entry is not read.
  PACKAGE_ALIASES = Set{"role", "permission", "role_or_permission", "abilities", "ability", "scopes", "scope"}

  GATE_CALL = /\A(?:\$this\s*->\s*authorize|Gate::authorize)\s*\(\s*(?:'([^'\\$]*)'|"([^"\\$]*)")\s*[,)]/

  # What the middleware `entry` requires, or nil when it does not concern
  # who the caller is. `klass` is the class its alias names in the app, nil
  # when the app's alias table does not name one.
  def middleware(entry : String, klass : String? = nil) : Access::CNF?
    return [[Access::Atom.new(:authenticated)]] if entry.matches?(AUTH_ALIAS)
    name, _, args = entry.partition(':')
    # Only signed-out callers pass: no atom says that.
    return unresolved(entry) if name == "guest"
    return can(args, entry) if name == "can"
    params = klass ? PACKAGE_PARAMS[package_key(klass)]? : (Params::Unread if PACKAGE_ALIASES.includes?(name))
    return unless params
    return unresolved(entry) if params.unread? || args.blank?
    case params
    when .any_role?, .any_permission?
      # `role:admin|editor,api`: after the comma comes the auth guard's name.
      kind = params.any_role? ? Access::Kind::Role : Access::Kind::Permission
      [args.partition(',')[0].split('|').map { |value| value_atom(kind, value) }]
    when .all_scopes?
      args.split(',').map { |value| [value_atom(Access::Kind::Scope, value)] }
    else
      [args.split(',').map { |value| value_atom(Access::Kind::Scope, value) }]
    end
  end

  # `$this->authorize('update', $post)` / `Gate::authorize('update', ...)`.
  def gate_call(call : String) : Access::CNF
    return unresolved(call) unless found = call.match(GATE_CALL)
    ability = (found[1]? || found[2]?).to_s
    ability.empty? ? unresolved(call) : [[Access::Atom.new(:permission, ability)]]
  end

  # Each clause also holds when `note` does: a condition or a withdrawal
  # noir could not settle decides whether the middleware applies.
  def liftable(clauses : Array(Access::Clause), note : String) : Array(Access::Clause)
    lift = Access::Atom.new(:unresolved, note)
    clauses.map { |clause| Access::Clause.new(clause.any_of + [lift], clause.source, clause.path, clause.line) }
  end

  # `Authorize::handle($request, $next, $ability, ...$models)`: one ability,
  # then the route parameters or classes the policy is resolved from.
  private def can(args : String, entry : String) : Access::CNF
    ability = args.partition(',')[0].strip
    return unresolved(entry) if ability.empty? || ability.includes?('|')
    [[Access::Atom.new(:permission, ability)]]
  end

  # A `*` is a wildcard only when Spatie's `enable_wildcard_permission` is set.
  private def value_atom(kind : Access::Kind, value : String) : Access::Atom
    value = value.strip
    value.empty? || value.includes?('*') ? Access::Atom.new(:unresolved, value) : Access::Atom.new(kind, value)
  end

  private def package_key(klass : String) : String
    klass.lchop('\\').sub("Spatie\\Permission\\Middlewares\\", "Spatie\\Permission\\Middleware\\")
  end

  private def unresolved(fragment : String) : Access::CNF
    [[Access::Atom.new(:unresolved, fragment)]]
  end
end
