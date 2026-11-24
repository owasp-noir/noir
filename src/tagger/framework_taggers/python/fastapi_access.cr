require "../../../models/access"
require "../../../utils/top_level_split"

# Reads FastAPI's own security vocabulary into a requirement: the
# `fastapi.security` schemes, OAuth2 scopes a dependency checks through
# `SecurityScopes`, and a dependency comparing the caller's role.
module FastAPIAccess
  extend self

  # Their `__call__` refuses a request without the credential unless built
  # with `auto_error=False`.
  SCHEMES = %w[OAuth2 OAuth2PasswordBearer OAuth2AuthorizationCodeBearer OpenIdConnect
    HTTPBase HTTPBasic HTTPBearer HTTPDigest APIKeyHeader APIKeyQuery APIKeyCookie]
  # `auto_error` is keyword-only on most schemes and at least the fifth
  # parameter on the others (`OAuth2PasswordBearer(tokenUrl, scheme_name,
  # scopes, description, auto_error)`).
  POSITIONAL_AUTO_ERROR = 5
  KEYWORD               = /\A([A-Za-z_]\w*)\s*=(?!=)\s*(.*)\z/m
  STRING                = /\A[rRuU]?(?:"([^"\\]*)"|'([^'\\]*)')\z/
  SPLIT                 = Noir::TopLevelSplit::Rules.new(empties: Noir::TopLevelSplit::Empties::DropAll)
  AUTHENTICATED         = Access::Atom.new(:authenticated)

  def scheme?(ctor : String) : Bool
    SCHEMES.includes?(ctor.split('.').last)
  end

  # A scheme instance built with `args`. Without `auto_error=False` it
  # refuses a caller who sends no credential; with it, it hands the
  # dependency `None` and the dependency decides.
  def scheme(args : Array(String), source : String) : Access::CNF
    positional = 0
    args.each do |arg|
      return unresolved(source) if arg.starts_with?('*')
      if kw = arg.match(KEYWORD)
        next unless kw[1] == "auto_error"
        return kw[2].strip == "True" ? [[AUTHENTICATED]] : unresolved(source)
      end
      positional += 1
    end
    positional >= POSITIONAL_AUTO_ERROR ? unresolved(source) : [[AUTHENTICATED]]
  end

  # The atoms of a `scopes=[...]` value: a string literal is a scope,
  # anything else is unresolved.
  def scope_atoms(value : String) : Array(Access::Atom)
    elements(value).map { |element| (text = string(element)) ? Access::Atom.new(:scope, text) : Access::Atom.new(:unresolved, element) }
  end

  # The pattern FastAPI documents for a dependency taking `SecurityScopes`:
  # every requested scope missing from the token refuses the caller.
  #
  #     for scope in security_scopes.scopes:
  #         if scope not in token_data.scopes:
  #             raise credentials_exception
  def checks_every_scope?(block : String) : Bool
    param = block.match(/\b([A-Za-z_]\w*)\s*:\s*SecurityScopes\b/).try(&.[1]) || return false
    block.matches?(/^[ \t]*for\s+(\w+)\s+in\s+#{Regex.escape(param)}\.scopes\s*:\s*\n[ \t]*if\s+\1\s+not\s+in\s+[^\n]+:\s*(?:raise\b|\n[ \t]*raise\b)/m)
  end

  # `cond`, under which a dependency refuses, read as a role comparison:
  # `user.role != ref` and `ref not in user.roles` name one role,
  # `user.role not in ref` a collection of them. `{caller, ref, collection?}`.
  # Anything joined with `and` / `or`, negated or compared with `==` is not
  # one comparison, so it is not read.
  def role_comparison(cond : String) : {String, String, Bool}?
    cond = cond.strip
    return if cond.gsub(/"[^"]*"|'[^']*'/, "''").matches?(/\b(?:and|or)\b|\A\s*not\s/)
    if m = cond.match(/\A([A-Za-z_][\w.]*?)\.role\s*!=\s*(\S.*)\z/)
      {m[1], m[2].strip, false}
    elsif m = cond.match(/\A([A-Za-z_][\w.]*?)\.role\s+not\s+in\s+(\S.*)\z/)
      {m[1], m[2].strip, true}
    elsif m = cond.match(/\A(\S.*?)\s+not\s+in\s+([A-Za-z_][\w.]*?)\.roles\z/)
      {m[2], m[1].strip, false}
    end
  end

  # The roles `value` (the literal a comparison's reference holds, or nil
  # when it could not be read) admits. `ref` is the reference as written.
  def role_atoms(value : String?, ref : String, collection : Bool) : Array(Access::Atom)
    return [Access::Atom.new(:unresolved, ref)] unless value
    unless collection
      return [(text = string(value)) ? Access::Atom.new(:role, text) : Access::Atom.new(:unresolved, ref)]
    end
    # `x not in "admin"` is a substring test.
    return [Access::Atom.new(:unresolved, ref)] unless value.starts_with?('[') || value.starts_with?('(') || value.starts_with?('{')
    roles = elements(value).map { |element| (text = string(element)) ? Access::Atom.new(:role, text) : Access::Atom.new(:unresolved, element) }
    roles.empty? ? [Access::Atom.new(:unresolved, ref)] : roles
  end

  # A test that a value is missing: `not user`, `user is None`. Not
  # `not settings.enabled`, which reads a field of a value that is there.
  def absence_test?(cond : String) : Bool
    cond.strip.matches?(/\A(?:not\s+[A-Za-z_]\w*|[A-Za-z_]\w*\s+(?:is|==)\s+None)\z/)
  end

  # Each clause also holds when the setting `note` names lets every caller
  # through.
  def liftable(cnf : Access::CNF, note : String) : Access::CNF
    lift = Access::Atom.new(:unresolved, note)
    cnf.map { |atoms| atoms + [lift] }
  end

  def unresolved(fragment : String) : Access::CNF
    [[Access::Atom.new(:unresolved, fragment)]]
  end

  private def elements(value : String) : Array(String)
    inner = value.strip
    return [inner] unless inner.size >= 2 && {'[' => ']', '(' => ')', '{' => '}'}[inner[0]]? == inner[-1]
    Noir::TopLevelSplit.split(inner[1...-1], ',', SPLIT).map(&.strip).reject(&.empty?)
  end

  private def string(text : String) : String?
    found = text.strip.match(STRING) || return
    found[1]? || found[2]?
  end
end
