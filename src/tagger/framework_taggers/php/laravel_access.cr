require "../../../models/access"
require "../../../minilexers/php_lexer"
require "../../../utils/top_level_split"

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

  # Laravel's own aliases (`Middleware::defaultAliases`), for an app whose
  # alias table does not list them.
  BUILTIN_CLASSES = {
    "auth"             => "Illuminate\\Auth\\Middleware\\Authenticate",
    "auth.basic"       => "Illuminate\\Auth\\Middleware\\AuthenticateWithBasicAuth",
    "auth.session"     => "Illuminate\\Session\\Middleware\\AuthenticateSession",
    "bindings"         => "Illuminate\\Routing\\Middleware\\SubstituteBindings",
    "cache.headers"    => "Illuminate\\Http\\Middleware\\SetCacheHeaders",
    "can"              => "Illuminate\\Auth\\Middleware\\Authorize",
    "guest"            => "Illuminate\\Auth\\Middleware\\RedirectIfAuthenticated",
    "password.confirm" => "Illuminate\\Auth\\Middleware\\RequirePassword",
    "precognitive"     => "Illuminate\\Foundation\\Http\\Middleware\\HandlePrecognitiveRequests",
    "signed"           => "Illuminate\\Routing\\Middleware\\ValidateSignature",
    "throttle"         => "Illuminate\\Routing\\Middleware\\ThrottleRequests",
    "verified"         => "Illuminate\\Auth\\Middleware\\EnsureEmailIsVerified",
  }

  # Package middleware that does not decide who may call (session, CORS).
  NON_ACCESS_CLASSES = Set{
    "Laravel\\Sanctum\\Http\\Middleware\\EnsureFrontendRequestsAreStateful",
    "Laravel\\Passport\\Http\\Middleware\\CreateFreshApiToken",
    "Fruitcake\\Cors\\HandleCors",
  }

  # The framework's classes that do decide who may call.
  ACCESS_CLASSES = Set{
    "Illuminate\\Auth\\Middleware\\Authenticate",
    "Illuminate\\Auth\\Middleware\\AuthenticateWithBasicAuth",
    "Illuminate\\Auth\\Middleware\\Authorize",
    "Illuminate\\Auth\\Middleware\\RedirectIfAuthenticated",
  }

  # The framework's default groups; an app that lists them adds members.
  DEFAULT_GROUPS = Set{"web", "api"}

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
    case klass.try(&.lchop('\\'))
    when "Illuminate\\Auth\\Middleware\\Authenticate", "Illuminate\\Auth\\Middleware\\AuthenticateWithBasicAuth"
      return [[Access::Atom.new(:authenticated)]]
    when "Illuminate\\Auth\\Middleware\\Authorize"
      return can(args, entry)
    when "Illuminate\\Auth\\Middleware\\RedirectIfAuthenticated"
      return unresolved(entry)
    end
    params = klass ? PACKAGE_PARAMS[package_key(klass)]? : (Params::Unread if PACKAGE_ALIASES.includes?(name))
    return unless params
    return unresolved(entry) if params.unread? || args.blank?
    case params
    when .any_role?, .any_permission?
      # `role:admin|editor,api`: after the comma comes the auth guard's name.
      kind = params.any_role? ? Access::Kind::Role : Access::Kind::Permission
      [args.partition(',')[0].split('|').map { |value| value_atom(kind, value, entry) }]
    when .all_scopes?
      args.split(',').map { |value| [value_atom(Access::Kind::Scope, value, entry)] }
    else
      [args.split(',').map { |value| value_atom(Access::Kind::Scope, value, entry) }]
    end
  end

  # Whether the entry is known not to decide who may call: one of the
  # framework's classes or default groups, or a package's session or CORS
  # middleware. `klass` as for `middleware`.
  def non_access?(entry : String, klass : String? = nil) : Bool
    name = entry.partition(':')[0]
    klass ||= BUILTIN_CLASSES[name]?
    return DEFAULT_GROUPS.includes?(name) unless klass
    klass = klass.lchop('\\').partition(':')[0]
    return false if ACCESS_CLASSES.includes?(klass)
    klass.starts_with?("Illuminate\\") || NON_ACCESS_CLASSES.includes?(klass)
  end

  # The guard's conservative reading (signed in, plus what was not read)
  # whenever a clause is only unread text: a migrated tag is never weaker
  # than that unless every entry was read. `guest` is read: signed-out only.
  def floor(clauses : Array(Access::Clause), source : String) : Array(Access::Clause)
    unread = clauses.any? do |clause|
      clause.any_of.all?(&.kind.unresolved?) && !(clause.any_of.size == 1 && clause.any_of[0].value.to_s.matches?(/\Aguest(?::|\z)/))
    end
    return clauses unless unread && clauses.none?(&.any_of.==([Access::Atom.new(:authenticated)]))
    clauses + [Access::Clause.new([Access::Atom.new(:authenticated)], source)]
  end

  # The elements of a middleware value: an array literal's entries, or the
  # value itself.
  def elements(value : String) : Array(String)
    value = value.strip
    inner = if value.starts_with?('[') && closes_at_end?(value, 0)
              value[1...-1]
            elsif (open = value.match(/\Aarray\s*\(/i)) && closes_at_end?(value, open.end(0) - 1)
              value[open.end(0)...-1]
            end
    inner ? parts(inner, ',') : [value].reject(&.empty?)
  end

  # The arguments of the call whose `(` is at `open`; nil when it never closes.
  def arguments(text : String, open : Int32) : Array(String)?
    close = Noir::PhpLexer.new(text, php_mode: true).matching_delimiter(open) || return
    parts(text[(open + 1)...close], ',')
  end

  # The value starting at `start`: up to a top-level `,` / `;` or a bracket
  # it did not open.
  def value_at(text : String, start : Int32) : String
    text[start...Noir::PhpLexer.new(text, php_mode: true).expression_end(start)].strip
  end

  # The middleware string a list element evaluates to: a literal, `Foo::class`,
  # `Foo::using('a', 'b')` (`Foo:a,b`, what `using` returns) and their
  # concatenation, with class names passed through `qualify`. Nil for
  # anything else (a variable, a call, a constant).
  def entry(element : String, & : String -> String) : String?
    pieces = parts(element, '.')
    return if pieces.empty?
    String.build do |io|
      pieces.each do |piece|
        if literal = literal(piece)
          io << literal
        elsif found = piece.match(/\A(\\?[A-Za-z_][\w\\]*)::class\z/)
          io << yield found[1]
        elsif (found = piece.match(/\A(\\?[A-Za-z_][\w\\]*)::using\s*\(/)) && closes_at_end?(piece, found.end(0) - 1) && (args = arguments(piece, found.end(0) - 1))
          values = args.map { |arg| literal(arg) || return }
          io << yield found[1]
          io << ':' << values.join(',') unless values.empty?
        else
          return
        end
      end
    end
  end

  def literal(text : String) : String?
    return unless found = text.strip.match(/\A'((?:[^'\\]|\\.)*)'\z|\A"((?:[^"\\$]|\\.)*)"\z/m)
    (found[1]? || found[2]?).to_s.gsub(/\\(['"\\])/, "\\1")
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

  # Whether the bracket at `open` is closed by the last character of `text`.
  private def closes_at_end?(text : String, open : Int32) : Bool
    Noir::PhpLexer.new(text, php_mode: true).matching_delimiter(open) == text.size - 1
  end

  private def parts(text : String, separator : Char) : Array(String)
    Noir::TopLevelSplit.split(text, separator, Noir::TopLevelSplit::Rules.new(empties: Noir::TopLevelSplit::Empties::DropAll))
  end

  # A `*` is a wildcard only when Spatie's `enable_wildcard_permission` is set.
  private def value_atom(kind : Access::Kind, value : String, entry : String) : Access::Atom
    value = value.strip
    return Access::Atom.new(:unresolved, entry) if value.empty?
    value.includes?('*') ? Access::Atom.new(:unresolved, value) : Access::Atom.new(kind, value)
  end

  private def package_key(klass : String) : String
    klass.lchop('\\').sub("Spatie\\Permission\\Middlewares\\", "Spatie\\Permission\\Middleware\\")
  end

  private def unresolved(fragment : String) : Access::CNF
    [[Access::Atom.new(:unresolved, fragment)]]
  end
end
