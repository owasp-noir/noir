require "../../../models/access"
require "../../../utils/top_level_split"
require "../../../utils/js_literal_scanner"

# Reads the NestJS metadata decorators a roles, permissions or policies guard
# checks (`@Roles('admin')`, `@Permissions(...)`, `@SetMetadata('roles', [...])`,
# `@CheckPolicies(...)`) into a requirement. Such a decorator enforces nothing
# itself: a guard in application code reads it and decides whether the route
# is checked, whether class metadata counts, and whether several values mean
# any or all. What that guard does is read only when its source is at hand.
module NestjsAccess
  extend self

  # One decorator's values and its text.
  record Use, atoms : Array(Access::Atom), text : String

  # Which metadata a guard's `Reflector` call takes: the handler's alone,
  # the class's alone, the handler's over the class's
  # (`getAllAndOverride([handler, class])`), or both (`getAllAndMerge`).
  enum Targets
    Handler
    Class
    Override
    Merge
  end

  # A bound guard that reads one kind of metadata. Nil fields were not read:
  # the guard's source is not at hand, or it reads the key more than one way.
  record Reader, targets : Targets?, any_of : Bool?

  LITERAL        = /\A\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)"|`([^`$\\]*)`)\s*\z/m
  IDENTIFIER     = /\A[A-Za-z_$][\w$]*\z/
  MEMBER         = /\A([A-Za-z_$][\w$]*)\.([A-Za-z_$][\w$]*)\z/
  REFLECTOR_CALL = /\breflector\s*\.\s*(get|getAllAndOverride|getAllAndMerge)\s*(?:<[^(]*?>)?\s*\(/
  # The metadata key a guard reads for each kind, judged by its name
  # (`'roles'`, `ROLES_KEY`, a `Reflector.createDecorator` named `Roles`).
  KIND_KEYS = {
    Access::Kind::Role       => /role/i,
    Access::Kind::Permission => /permission/i,
    Access::Kind::Scope      => /scope/i,
  }

  private def kind(name : String, args : Array(String)) : Access::Kind?
    case name
    when "Roles"                             then Access::Kind::Role
    when "Permissions", "RequirePermissions" then Access::Kind::Permission
    when "Scopes"                            then Access::Kind::Scope
    when "CheckPolicies", "CheckAbilities"   then Access::Kind::Unresolved
    when "SetMetadata"                       then Access::Kind::Role if args.first?.try { |key| literal(key) } == "roles"
    end
  end

  # The kind of metadata the decorator sets and its values: a literal, or a
  # string constant or enum member declared in `code` (the decorator's own
  # file); anything else is an unresolved atom. Nil for a decorator that
  # sets no such metadata.
  def metadata(name : String, args : Array(String), text : String, code : String) : {Access::Kind, Array(Access::Atom)}?
    kind = kind(name, args) || return
    # A CASL policy handler or ability rule is code, not a value.
    return {kind, [Access::Atom.new(:unresolved, text)]} if kind.unresolved?
    values = name == "SetMetadata" ? args[1, 1] : args
    # `@Roles(['admin'])`: `Reflector.createDecorator<string[]>()` takes one array.
    if values.size == 1 && (only = values[0].strip).starts_with?('[') && only.ends_with?(']')
      values = Noir::TopLevelSplit.split(only[1...-1], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS)
    end
    values = values.map(&.strip).reject(&.empty?)
    return {kind, [Access::Atom.new(:unresolved, text)]} if values.empty?
    {kind, values.map { |value| (resolved = literal(value) || constant(value, code)) ? Access::Atom.new(kind, resolved) : Access::Atom.new(:unresolved, value) }}
  end

  # How the guard whose class body is `body` reads `kind` metadata; nil when
  # it makes no `Reflector` call on a key named for that kind.
  def reader(body : String, kind : Access::Kind) : Reader?
    key = KIND_KEYS[kind]? || return
    targets = [] of Targets?
    body.scan(REFLECTOR_CALL) do |call|
      close = Noir::JSLiteralScanner.find_matching_paren(body, call.end(0) - 1) || next
      args = body[call.end(0)...close]
      next unless Noir::TopLevelSplit.split(args, ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).first?.try(&.matches?(key))
      targets << targets(call[1], args)
    end
    return if targets.empty?
    # ponytail: `.some(` / `.every(` anywhere in the class decides; reading
    # which list each one walks is the upgrade.
    some = body.matches?(/\.some\s*\(/)
    every = body.matches?(/\.every\s*\(/)
    any_of = if some != every
               some
             elsif !some && body.matches?(/\.includes\s*\(/)
               true
             end
    Reader.new(targets.uniq.size == 1 ? targets[0] : nil, any_of)
  end

  private def targets(method : String, args : String) : Targets?
    handler = args.index("getHandler")
    klass = args.index("getClass")
    case method
    when "get"
      if handler && !klass
        Targets::Handler
      elsif klass && !handler
        Targets::Class
      end
    when "getAllAndOverride" then Targets::Override if handler && klass && handler < klass
    when "getAllAndMerge"    then Targets::Merge if handler && klass
    end
  end

  # What a route's metadata of one kind requires, given the method's and the
  # class's top-most decorator of that kind and the bound guard reading it
  # (nil: none visible). What the guard was not read for stays unresolved:
  # with no reader, the decorator's text is an alternative in every clause,
  # so no caller reads as denied on a check that may not run; class values
  # count only if the guard reads class metadata, so they too carry the class
  # decorator as an alternative; several values need every one only under an
  # `every` check, so an unread combination adds the decorator as a clause.
  def requirement(method : Use?, klass : Use?, reader : Reader?) : Access::CNF
    primary = method || klass || return Access::CNF.new
    targets = reader.try(&.targets)
    certain, optional =
      case targets
      in Targets::Override then {primary.atoms, [] of Access::Atom}
      in Targets::Merge    then {(method.try(&.atoms) || [] of Access::Atom) + (klass.try(&.atoms) || [] of Access::Atom), [] of Access::Atom}
      in Targets::Handler  then {(method.try(&.atoms) || return Access::CNF.new), [] of Access::Atom}
      in Targets::Class    then {(klass.try(&.atoms) || return Access::CNF.new), [] of Access::Atom}
      in Nil               then {method.try(&.atoms) || [] of Access::Atom, klass.try(&.atoms) || [] of Access::Atom}
      end
    alternatives = reader ? [] of Access::Atom : [Access::Atom.new(:unresolved, primary.text)]
    class_alternative = klass.try { |use| Access::Atom.new(:unresolved, use.text) } if targets.nil?
    if reader.try(&.any_of) == false
      certain.map { |atom| [atom] + alternatives } + optional.map { |atom| [atom, class_alternative].compact + alternatives }
    else
      # Unread targets: class values beside method values may be replaced by
      # them (`getAllAndOverride`), so only the class decorator stands in.
      atoms = certain.empty? ? optional : certain
      clause = atoms + [class_alternative].compact + alternatives
      reader.try(&.any_of) || (certain + optional).size <= 1 ? [clause] : [clause, [Access::Atom.new(:unresolved, primary.text)]]
    end
  end

  private def literal(text : String) : String?
    return unless found = text.match(LITERAL)
    (found[1]? || found[2]? || found[3]?).to_s.gsub(/\\(.)/, "\\1")
  end

  # `ADMIN` from a top-level `const ADMIN = 'admin'`; `Role.Admin` from a
  # string `enum Role { Admin = 'admin' }` or a `const Role = { Admin: 'admin' }`.
  # A numeric enum member is no string, so it stays unread.
  private def constant(text : String, code : String) : String?
    if text.matches?(IDENTIFIER)
      found = code.match(/^(?:export\s+)?const\s+#{Regex.escape(text)}\s*(?::\s*string\s*)?=\s*([^;\n]+?)\s*(?:as\s+const\s*)?;?\s*$/m)
      return found.try { |m| literal(m[1]) }
    end
    return unless member = text.match(MEMBER)
    owner = Regex.escape(member[1])
    body = code.match(/^(?:export\s+)?(?:const\s+)?enum\s+#{owner}\s*\{([^}]*)\}/m).try(&.[1])
    separator = "="
    unless body
      body = code.match(/^(?:export\s+)?const\s+#{owner}\s*(?::[^=]*)?=\s*\{([^{}]*)\}/m).try(&.[1])
      separator = ":"
    end
    found = body.try(&.match(/(?:\A|[,\s])['"]?#{Regex.escape(member[2])}['"]?\s*#{separator}\s*('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")/))
    found.try { |m| literal(m[1]) }
  end
end
