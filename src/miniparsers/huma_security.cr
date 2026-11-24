require "../models/access"
require "../utils/c_comments"
require "../utils/top_level_split"

# Reads a Huma `[]map[string][]string{...}` security literal into what it
# asks of a caller. Huma only documents `Operation.Security`: whatever
# enforces a scheme is application code noir does not read, and without the
# scheme registry two schemes cannot be told apart. So each scheme reads as
# a credential plus that unread check, each scope as a `scope` atom.
# Alternatives are any-of, the schemes of one alternative all-of.
module HumaSecurity
  extend self

  ENTRY = /\A"([^"\\]*)"\s*:\s*(.+)\z/m
  LIST  = /\A(?:\[\]string\s*)?\{(.*)\}\z/m
  WORD  = /\A"([^"\\]*)"\z/
  RULES = Noir::TopLevelSplit::Rules.new(quotes: "\"'`", empties: Noir::TopLevelSplit::Empties::DropAll)

  # Nil when an alternative admits anyone (`{}`, or an empty list).
  def cnf(literal : String) : Access::CNF?
    code = Noir::CComments.strip(literal, quotes: %("'), raw_quotes: "`")
    open = code.index('{') || return unresolved(literal)
    close = code.rindex('}') || return unresolved(literal)
    alternatives = Noir::TopLevelSplit.split(code[open + 1...close], ',', RULES).map { |element| alternative(element.strip) }
    return if alternatives.empty? || alternatives.any?(&.empty?)
    joined = alternatives.reduce do |product, alternative|
      break capped(alternatives, literal) if product.size > Access::MAX_CLAUSES || alternative.size > Access::MAX_CLAUSES
      Access.either(product, alternative)
    end
    joined.size > Access::MAX_CLAUSES ? capped(alternatives, literal) : joined
  end

  # One element of the list: a map literal, or anything else (a variable)
  # read as unknown.
  private def alternative(element : String) : Access::CNF
    return unresolved(element) unless found = element.match(/\A\{(.*)\}\z/m)
    cnf = Access::CNF.new
    Noir::TopLevelSplit.split(found[1], ',', RULES).each do |entry|
      named = entry.match(ENTRY)
      cnf << [Access::Atom.new(:authenticated)] << [Access::Atom.new(:unresolved, named ? named[1] : entry)]
      cnf.concat(scopes(named[2].strip, named[1])) if named
    end
    cnf.uniq
  end

  # A nil `[]string` holds no scopes, like `{}`.
  private def scopes(value : String, name : String) : Access::CNF
    return Access::CNF.new if value == "nil"
    list = value.match(LIST) || return unresolved("#{name}: #{value}")
    Noir::TopLevelSplit.split(list[1], ',', RULES).map do |item|
      word = item.match(WORD).try(&.[1]).presence || return unresolved("#{name}: #{value}")
      [Access::Atom.new(:scope, word)]
    end
  end

  # Past the cap: every alternative that names a scheme refuses anonymous
  # callers.
  private def capped(alternatives : Array(Access::CNF), literal : String) : Access::CNF
    floor = alternatives.all?(&.includes?([Access::Atom.new(:authenticated)]))
    (floor ? [[Access::Atom.new(:authenticated)]] : Access::CNF.new) + unresolved(literal)
  end

  private def unresolved(text : String) : Access::CNF
    [[Access::Atom.new(:unresolved, text)]]
  end
end
