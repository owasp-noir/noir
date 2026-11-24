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
  KEEP                  = Noir::TopLevelSplit::Rules.new(empties: Noir::TopLevelSplit::Empties::Keep)
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
    values = elements(value) || return [Access::Atom.new(:unresolved, value.strip)]
    values.map { |element| (text = literal(element)) ? Access::Atom.new(:scope, text) : Access::Atom.new(:unresolved, element) }
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

  # `cond` read as a role comparison of `caller`, in the polarity a
  # refusal under it takes: refusing when `positive` holds (`user.role !=
  # ref`, `user.role not in ref`, `ref not in user.roles`), or when it fails
  # (`user.role == ref`, `user.role in ref`, `ref in user.roles`, ahead of
  # an unconditional raise). `{caller, ref, collection?}`. Anything joined
  # with `and` / `or` or negated is not one comparison.
  def role_comparison(cond : String, positive : Bool = true) : {String, String, Bool}?
    cond = cond.strip
    bare = cond.gsub(/"[^"]*"|'[^']*'/, "''")
    return if bare.matches?(/\b(?:and|or)\b|\A\s*not\s/)
    if positive
      if m = cond.match(/\A([A-Za-z_][\w.]*?)\.role\s*!=\s*(\S.*)\z/)
        {m[1], m[2].strip, false}
      elsif m = cond.match(/\A([A-Za-z_][\w.]*?)\.role\s+not\s+in\s+(\S.*)\z/)
        {m[1], m[2].strip, true}
      elsif m = cond.match(/\A(\S.*?)\s+not\s+in\s+([A-Za-z_][\w.]*?)\.roles\z/)
        {m[2], m[1].strip, false}
      end
    else
      return if bare.matches?(/\bnot\s+in\b/)
      if m = cond.match(/\A([A-Za-z_][\w.]*?)\.role\s*==\s*(\S.*)\z/)
        {m[1], m[2].strip, false}
      elsif m = cond.match(/\A([A-Za-z_][\w.]*?)\.role\s+in\s+(\S.*)\z/)
        {m[1], m[2].strip, true}
      elsif m = cond.match(/\A(\S.*?)\s+in\s+([A-Za-z_][\w.]*?)\.roles\z/)
        {m[2], m[1].strip, false}
      end
    end
  end

  # The roles `value` (the literal a comparison's reference holds, or nil
  # when it could not be read) admits. `ref` is the reference as written.
  def role_atoms(value : String?, ref : String, collection : Bool) : Array(Access::Atom)
    return [Access::Atom.new(:unresolved, ref)] unless value
    unless collection
      return [(text = literal(value)) ? Access::Atom.new(:role, text) : Access::Atom.new(:unresolved, ref)]
    end
    # `x not in "admin"` and `x not in ("admin")` are substring tests.
    values = elements(value)
    return [Access::Atom.new(:unresolved, ref)] if values.nil? || values.empty? || literal(value)
    values.map { |element| (text = literal(element)) ? Access::Atom.new(:role, text) : Access::Atom.new(:unresolved, element) }
  end

  # A test that a value is missing: `not user`, `user is None`. Not
  # `not settings.enabled`, which reads a field of a value that is there.
  def absence_test?(cond : String) : Bool
    cond.strip.matches?(/\A(?:not\s+[A-Za-z_]\w*|[A-Za-z_]\w*\s+(?:is|==)\s+None)\z/)
  end

  # A test that a value is there: `user`, `token is not None`.
  def presence_test?(cond : String) : Bool
    cond.strip.matches?(/\A(?:[A-Za-z_]\w*|[A-Za-z_]\w*\s+(?:is\s+not|!=)\s+None)\z/)
  end

  # The loop variable of the documented every-scope check, whose refusal
  # the scope atoms already carry.
  def scope_loop_variable(block : String) : String?
    param = block.match(/\b([A-Za-z_]\w*)\s*:\s*SecurityScopes\b/).try(&.[1]) || return
    block.match(/^[ \t]*for\s+(\w+)\s+in\s+#{Regex.escape(param)}\.scopes\s*:/m).try(&.[1])
  end

  # The string a Python string literal spells; nil for anything else, an
  # f-string among them.
  def literal(text : String) : String?
    found = text.strip.match(STRING) || return
    found[1]? || found[2]?
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

  # The elements of a list, set or tuple literal; nil for anything else. A
  # parenthesized value without a top-level comma is not a tuple.
  private def elements(value : String) : Array(String)?
    inner = value.strip
    return unless inner.size >= 2 && {'[' => ']', '(' => ')', '{' => '}'}[inner[0]]? == inner[-1]
    parts = Noir::TopLevelSplit.split(inner[1...-1], ',', KEEP)
    return if inner[0] == '(' && parts.size < 2
    parts.map(&.strip).reject(&.empty?)
  end
end
