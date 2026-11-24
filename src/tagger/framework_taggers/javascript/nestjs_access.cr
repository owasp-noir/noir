require "../../../models/access"
require "../../../utils/top_level_split"

# Reads the NestJS metadata decorators a roles, permissions or policies guard
# checks (`@Roles('admin')`, `@Permissions(...)`, `@SetMetadata('roles', [...])`,
# `@CheckPolicies(...)`) into a requirement.
module NestjsAccess
  extend self

  LITERAL    = /\A\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)"|`([^`$\\]*)`)\s*\z/m
  IDENTIFIER = /\A[A-Za-z_$][\w$]*\z/
  MEMBER     = /\A([A-Za-z_$][\w$]*)\.([A-Za-z_$][\w$]*)\z/

  private def kind(name : String, args : Array(String)) : Access::Kind?
    case name
    when "Roles"                             then Access::Kind::Role
    when "Permissions", "RequirePermissions" then Access::Kind::Permission
    when "Scopes"                            then Access::Kind::Scope
    when "CheckPolicies", "CheckAbilities"   then Access::Kind::Unresolved
    when "SetMetadata"                       then Access::Kind::Role if args.first?.try { |key| literal(key) } == "roles"
    end
  end

  # One clause over the decorator's values: the Nest docs' `RolesGuard`
  # admits a caller holding any one role (`requiredRoles.some(...)`). A
  # permissions or scopes guard is application code that may ask for every
  # value, so several of those also carry the decorator as an unresolved
  # clause. A value that is neither a literal nor a string constant or enum
  # member declared in `code` (the decorator's own file) is an unresolved
  # atom. Nil for a decorator that sets no such metadata.
  def metadata(name : String, args : Array(String), text : String, code : String) : {Access::Kind, Access::CNF}?
    kind = kind(name, args) || return
    # A CASL policy handler or ability rule is code, not a value.
    return {kind, unresolved(text)} if kind.unresolved?
    {kind, values(kind, name, args, text, code)}
  end

  private def values(kind : Access::Kind, name : String, args : Array(String), text : String, code : String) : Access::CNF
    values = name == "SetMetadata" ? args[1..]? || [] of String : args
    # `@Roles(['admin'])`: `Reflector.createDecorator<string[]>()` takes one array.
    if values.size == 1 && (only = values[0].strip).starts_with?('[') && only.ends_with?(']')
      values = Noir::TopLevelSplit.split(only[1...-1], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS)
    end
    values = values.map(&.strip).reject(&.empty?)
    return unresolved(text) if values.empty?
    atoms = values.map { |value| (resolved = literal(value) || constant(value, code)) ? Access::Atom.new(kind, resolved) : Access::Atom.new(:unresolved, value) }
    kind.role? || atoms.size == 1 ? [atoms] : [atoms, [Access::Atom.new(:unresolved, text)]]
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

  private def unresolved(text : String) : Access::CNF
    [[Access::Atom.new(:unresolved, text)]]
  end
end
