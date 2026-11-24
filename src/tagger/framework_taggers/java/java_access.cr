require "../../../models/access"
require "../../../utils/js_literal_scanner"
require "../../../utils/top_level_split"

# Reads the non-Spring Java guard vocabularies into a requirement: JSR-250
# and Quarkus annotations, Micronaut `@Secured`, Vaadin access annotations
# and Vert.x auth handlers. Role and permission values are compared as
# written: unlike Spring, none of these frameworks strips a `ROLE_` prefix.
module JavaAccess
  extend self

  # One annotation as written. `args` is the text between its parentheses,
  # nil when it has none.
  record Annotation, name : String, args : String?, text : String

  SPLIT   = Noir::TopLevelSplit::Rules.new(empties: Noir::TopLevelSplit::Empties::DropAll)
  LITERAL = /\A\s*"((?:[^"\\]|\\.)*)"\s*\z/m
  NAMED   = /\A\s*([A-Za-z_]\w*)\s*=(?!=)\s*(.*)\z/m

  # The `@name` annotation written on `lines[idx]` at or after column
  # `from`, its arguments read up to the balanced `)` across the following
  # lines. nil when it is not on that line, or when its parenthesis never
  # closes.
  def annotation_in(lines : Array(String), idx : Int32, name : String, from : Int32 = 0) : Annotation?
    return unless line = lines[idx]?
    return unless found = line.match(/@(?:[\w.]*\.)?#{name}\b/, from)
    text = lines[idx, 40].join('\n')
    rest = found.end(0)
    while rest < text.size && text[rest].whitespace?
      rest += 1
    end
    return Annotation.new(name, nil, found[0]) unless text[rest]? == '('
    return unless close = Noir::JSLiteralScanner.find_matching_paren(text, rest)
    Annotation.new(name, text[(rest + 1)...close], text[found.begin(0)..close].gsub(/\s*\n\s*/, " "))
  end

  # Quarkus security annotations. `checkers` holds the permission names an
  # app `@PermissionChecker` decides; nil when one has a name noir cannot read.
  def quarkus(ann : Annotation, checkers : Set(String)? = Set(String).new) : Access::CNF
    case ann.name
    when "Authenticated"
      [[Access::Atom.new(:authenticated)]]
    when "PermitAll"
      Access::CNF.new
    when "DenyAll"
      [[Access::Atom.new(:deny)]]
    when "RolesAllowed"
      # `**` is any signed-in caller; `@Authenticated` is defined as it.
      list(ann) { |value| value == "**" ? Access::Atom.new(:authenticated) : Access::Atom.new(:role, value) }
    when "PermissionsAllowed"
      permissions(ann, checkers)
    else
      unresolved(ann.text)
    end
  end

  # Any one permission admits the caller unless `inclusive = true`, which
  # needs all. A custom `permission` class or `params` decides in app code.
  private def permissions(ann : Annotation, checkers : Set(String)?) : Access::CNF
    return unresolved(ann.text) unless args = ann.args
    _, named = arguments(args)
    inclusive = named["inclusive"]?
    return unresolved(ann.text) unless (named.keys - ["value", "inclusive"]).empty? && inclusive.in?(nil, "true", "false")
    cnf = list(ann, ["inclusive"]) do |value|
      checkers.try(&.includes?(value)) == false ? Access::Atom.new(:permission, value) : Access::Atom.new(:unresolved, value)
    end
    inclusive == "true" ? cnf.flat_map { |atoms| atoms.map { |atom| [atom] } } : cnf
  end

  # A Quarkus HTTP permission's policy. A named role policy without
  # `roles-allowed` defaults to `**`; a name with no `quarkus.http.auth.policy`
  # keys is an app `HttpSecurityPolicy` bean.
  def quarkus_policy(policy : String, roles_allowed : String?, defined : Bool) : Access::CNF
    case policy.downcase
    when "permit"        then return Access::CNF.new
    when "deny"          then return [[Access::Atom.new(:deny)]]
    when "authenticated" then return [[Access::Atom.new(:authenticated)]]
    end
    return unresolved(policy) unless defined
    return [[Access::Atom.new(:authenticated)]] unless roles_allowed
    roles = roles_allowed.split(',').map(&.strip).reject(&.empty?)
    return unresolved(roles_allowed) if roles.empty?
    [roles.map do |role|
      if role == "**"
        Access::Atom.new(:authenticated)
      elsif placeholder?(role)
        Access::Atom.new(:unresolved, role)
      else
        Access::Atom.new(:role, role)
      end
    end]
  end

  # Micronaut's `SecuredAnnotationRule`: `DENY_ALL` anywhere rejects first;
  # otherwise any one value admits, and every caller holds `IS_ANONYMOUS`.
  # An unread value may be `DENY_ALL`, so it leaves the whole list unread.
  def micronaut(ann : Annotation) : Access::CNF
    return unresolved(ann.text) unless (args = ann.args) && (values = values(args))
    atoms = values.map { |value| micronaut_atom(value) }
    return [[Access::Atom.new(:deny)]] if atoms.any? { |atom| atom.try(&.kind.deny?) }
    return unresolved(ann.text) if values.empty? || atoms.any? { |atom| atom.try(&.kind.unresolved?) }
    return Access::CNF.new if atoms.any?(Nil)
    [atoms.compact]
  end

  # nil for `IS_ANONYMOUS`, which every caller holds. The `SecurityRule`
  # constants hold `"isAnonymous()"`, `"isAuthenticated()"` and
  # `"denyAll()"`; a literal `"IS_ANONYMOUS"` is a role name like any other.
  private def micronaut_atom(value : String) : Access::Atom?
    if text = literal(value)
      case text
      when "isAnonymous()"     then nil
      when "isAuthenticated()" then Access::Atom.new(:authenticated)
      when "denyAll()"         then Access::Atom.new(:deny)
      else
        # `#{...}` is an evaluated expression, not a role.
        text.starts_with?("\#{") ? Access::Atom.new(:unresolved, value.strip) : Access::Atom.new(:role, text)
      end
    else
      case value.strip.sub(/\A(?:[\w.]*\.)?SecurityRule\s*\.\s*/, "")
      when "IS_ANONYMOUS"     then nil
      when "IS_AUTHENTICATED" then Access::Atom.new(:authenticated)
      when "DENY_ALL"         then Access::Atom.new(:deny)
      else                         Access::Atom.new(:unresolved, value.strip)
      end
    end
  end

  # Vaadin's `AccessAnnotationChecker.hasAccess` over the annotations of one
  # element: `@DenyAll` refuses, then `@AnonymousAllowed` admits everyone,
  # then a signed-in caller is required, then `@RolesAllowed` (any one role,
  # through `isUserInRole`) or `@PermitAll`. nil when none is present.
  def vaadin(annotations : Array(Annotation)) : Access::CNF?
    names = annotations.map(&.name)
    return [[Access::Atom.new(:deny)]] if names.includes?("DenyAll")
    return Access::CNF.new if names.includes?("AnonymousAllowed")
    if roles = annotations.find { |item| item.name == "RolesAllowed" }
      # What `isUserInRole("**")` answers depends on the servlet container
      # and on Spring Security.
      return [[Access::Atom.new(:authenticated)]] + list(roles) { |value| value == "**" ? Access::Atom.new(:unresolved, value) : Access::Atom.new(:role, value) }
    end
    [[Access::Atom.new(:authenticated)]] if names.includes?("PermitAll")
  end

  VERTX_GRANT  = /\A\s*(RoleBasedAuthorization|PermissionBasedAuthorization)\s*\.\s*create\s*\(\s*("(?:[^"\\]|\\.)*")\s*\)\s*\z/
  VERTX_CREATE = /\A([A-Z][\w$]*)\s*\.\s*create\s*\(/
  # vertx-web's authentication handlers: each refuses a caller without
  # valid credentials and checks nothing else unless configured further.
  VERTX_AUTHN = Set{"JWTAuthHandler", "BasicAuthHandler", "DigestAuthHandler", "OAuth2AuthHandler", "RedirectAuthHandler",
                    "APIKeyHandler", "WebAuthn4JHandler", "WebAuthnHandler", "OtpAuthHandler", "SimpleAuthenticationHandler"}
  # vertx-web handlers that check no identity.
  VERTX_PASSIVE = Set{"BodyHandler", "CorsHandler", "LoggerHandler", "StaticHandler", "SessionHandler", "TimeoutHandler",
                      "ResponseTimeHandler", "ResponseContentTypeHandler", "FaviconHandler", "ErrorHandler", "CSRFHandler",
                      "HSTSHandler", "CSPHandler", "XFrameHandler", "MethodOverrideHandler", "TemplateHandler"}

  # What one Vert.x handler requires. vertx-web's authentication handlers
  # need a signed-in caller; `AuthorizationHandler.create(RoleBasedAuthorization
  # .create("x"))` a role (a permission for `PermissionBasedAuthorization`);
  # the handlers in VERTX_PASSIVE nothing. A call chained on a handler, a
  # non-literal authorization and any other handler are unread, except a
  # route's own `last` handler that `unread` finds no guard in: it serves
  # the request.
  def vertx_handler(expression : String, last : Bool, &unread : String -> Bool) : Access::CNF
    text = expression.strip
    if (call = text.match(VERTX_CREATE)) && (close = Noir::JSLiteralScanner.find_matching_paren(text, call.end(0) - 1))
      name = call[1]
      chain = chained_calls(text, close)
      return Access::CNF.new if VERTX_PASSIVE.includes?(name)
      if name == "AuthorizationHandler"
        args = text[call.end(0)...close]
        grant = args.match(VERTX_GRANT)
        value = grant.try { |found| literal(found[2]) }
        cnf = if grant && value
                [[Access::Atom.new(grant[1] == "RoleBasedAuthorization" ? Access::Kind::Role : Access::Kind::Permission, value)]]
              else
                [[Access::Atom.new(:unresolved, args.strip)]]
              end
        # Providers say who holds an authorization, not what is required.
        chain.reject!(&.starts_with?(".addAuthorizationProvider"))
      elsif VERTX_AUTHN.includes?(name)
        cnf = [[Access::Atom.new(:authenticated)]]
      end
      if cnf
        cnf << [Access::Atom.new(:unresolved, chain.join)] unless chain.empty?
        return cnf
      end
    end
    return Access::CNF.new if last && !unread.call(text)
    unresolved(text.lines.find { |line| unread.call(line) }.try(&.strip) || text.lines.first?.try(&.strip) || text)
  end

  # The `.name(..)` calls chained after the `)` at `close`.
  private def chained_calls(text : String, close : Int32) : Array(String)
    chain = [] of String
    finish = close
    while (call = text[(finish + 1)..].match(/\A\s*\.\s*[A-Za-z_$][\w$]*\s*\(/)) &&
          (call_close = Noir::JSLiteralScanner.find_matching_paren(text, finish + call.end(0)))
      chain << text[(finish + 1)..call_close].strip
      finish = call_close
    end
    # A chain that does not parse to the end is kept whole.
    rest = text[(finish + 1)..].strip.rchop(';').strip
    chain << rest unless rest.empty?
    chain
  end

  # `clauses` with a signed-in clause added when none of them already
  # refuses an anonymous caller: for a guard its tagger judges to refuse
  # them, whose check noir could not read in full.
  def signed_in(clauses : Array(Access::Clause), source : String, path : String? = nil, line : Int32? = nil) : Array(Access::Clause)
    refuses = clauses.any? do |clause|
      clause.any_of.all? { |atom| atom.kind.in?(Access::Kind::Role, Access::Kind::Permission, Access::Kind::Scope, Access::Kind::Authenticated, Access::Kind::Deny) }
    end
    refuses ? clauses : [Access::Clause.new([Access::Atom.new(:authenticated)], source, path, line)] + clauses
  end

  # One clause over the values of the annotation's array element, each
  # literal mapped by the block; any other value is an unresolved atom.
  private def list(ann : Annotation, keys : Array(String) = [] of String, & : String -> Access::Atom) : Access::CNF
    return unresolved(ann.text) unless (args = ann.args) && (values = values(args, keys)) && values.present?
    [values.map { |value| (text = literal(value)) ? yield(text) : Access::Atom.new(:unresolved, value.strip) }]
  end

  # The elements of the annotation's `value`: positional (Kotlin varargs
  # included) or `value = ...`, an array written `{..}`, `[..]` or
  # `arrayOf(..)` fanned out. nil when the value is given twice, or when an
  # element other than `value` and `keys` is given.
  private def values(args : String, keys : Array(String) = [] of String) : Array(String)?
    positional, named = arguments(args)
    return unless (named.keys - ["value"] - keys).empty?
    if value = named["value"]?
      return unless positional.empty?
      positional = [value]
    end
    positional.flat_map do |item|
      inner = item.strip
      if (inner.starts_with?('{') && inner.ends_with?('}')) || (inner.starts_with?('[') && inner.ends_with?(']'))
        comma_items(inner[1...-1])
      elsif array = inner.match(/\AarrayOf\s*\((.*)\)\z/m)
        comma_items(array[1])
      else
        [inner]
      end
    end
  end

  private def arguments(args : String) : {Array(String), Hash(String, String)}
    positional = [] of String
    named = Hash(String, String).new
    comma_items(args).each do |part|
      if found = part.match(NAMED)
        named[found[1]] = found[2].strip
      else
        positional << part
      end
    end
    {positional, named}
  end

  private def comma_items(text : String) : Array(String)
    Noir::TopLevelSplit.split(text, ',', SPLIT).map(&.strip).reject(&.empty?)
  end

  # A Java or Kotlin string literal; a template or `${...}` property
  # expression is not its value.
  private def literal(text : String) : String?
    return unless found = text.match(LITERAL)
    return if placeholder?(found[1])
    found[1].gsub(/\\(.)/, "\\1")
  end

  private def placeholder?(value : String) : Bool
    value.matches?(/\$[{A-Za-z_]/)
  end

  private def unresolved(fragment : String) : Access::CNF
    [[Access::Atom.new(:unresolved, fragment)]]
  end
end
