require "../../../models/access"
require "../../../utils/top_level_split"

# Reads Spring Security's authorization vocabulary into a requirement. Every
# Spring source goes through it: method-security annotations, `access("...")`
# and the filter-chain DSL calls (`hasRole("X")`, `authenticated()`).
module SpringAccess
  extend self

  VALUE_KEY = /\A\s*value\s*=\s*/
  CALL      = /\A([A-Za-z_$][\w$]*)\s*(?:\((.*)\))?\z/m
  LITERAL   = /\A\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')\s*\z/m

  def annotation(name : String, arg : String?) : Access::CNF
    source = arg ? "@#{name}(#{arg})" : "@#{name}"
    case name
    when "PreAuthorize", "PostAuthorize"
      return unresolved(source) unless arg && (expression = literal(arg.sub(VALUE_KEY, "")))
      expression(expression)
    when "Secured"
      list(arg, source) { |value| secured_atom(value) }
    when "RolesAllowed"
      list(arg, source) { |value| role_atom(value) }
    when "PermitAll"
      Access::CNF.new
    when "DenyAll"
      [[Access::Atom.new(:deny)]]
    else
      unresolved(source)
    end
  end

  # A SpEL expression or a chain DSL call. Text that is not one whole
  # expression (a dangling operator, unbalanced parens) is one unresolved
  # atom, never the part that did parse.
  def expression(text : String) : Access::CNF
    read(text.strip) || unresolved(text.strip)
  end

  private def read(text : String) : Access::CNF?
    return if text.empty?
    return unless ors = operands(text, "||", "or")
    return combine(ors, text) { |left, right| Access.either(left, right) } if ors.size > 1
    return unless ands = operands(text, "&&", "and")
    return combine(ands, text) { |left, right| Access.both(left, right) } if ands.size > 1
    return read(text[1...-1].strip) if text.starts_with?('(') && text.ends_with?(')') && operands(text[1...-1], "||", "or")
    primary(text)
  end

  private def combine(parts : Array(String), text : String, & : Access::CNF, Access::CNF -> Access::CNF) : Access::CNF?
    result = nil.as(Access::CNF?)
    parts.each do |part|
      return unless cnf = read(part.strip)
      result = result ? yield(result, cnf) : cnf
      # OR distributes over AND; past the cap the operand is left unread.
      return unresolved(text) if result.size > Access::MAX_CLAUSES
    end
    result
  end

  # `text` split at the top-level `symbol` / `word` operator (SpEL accepts
  # both spellings, in any case); nil when its brackets or quotes do not
  # balance, or when a ternary or Elvis sits at the top level: those bind
  # looser than `or`, so no operand of the split is a whole condition.
  private def operands(text : String, symbol : String, word : String) : Array(String)?
    chars = text.chars
    parts = [] of String
    depth = 0
    quote = nil.as(Char?)
    start = 0
    index = 0
    while index < chars.size
      char = chars[index]
      if open_quote = quote
        if char == '\\'
          index += 1
        elsif char == open_quote
          quote = nil
        end
      elsif char == '"' || char == '\''
        quote = char
      elsif char.in?('(', '[', '{')
        depth += 1
      elsif char.in?(')', ']', '}')
        return if (depth -= 1) < 0
      elsif depth == 0
        # Not safe navigation (`a?.b`) or a selection (`a.?[...]`).
        return if char == '?' && chars[index + 1]? != '.' && (index == 0 || chars[index - 1] != '.')
        width =
          if chars[index, symbol.size].join == symbol
            symbol.size
          elsif chars[index, word.size].join.downcase == word && (index == 0 || !word_char?(chars[index - 1])) && !word_char?(chars[index + word.size]?)
            word.size
          end
        if width
          parts << chars[start...index].join
          index += width
          start = index
          next
        end
      end
      index += 1
    end
    return if depth != 0 || quote
    parts << chars[start..].join
  end

  private def word_char?(char : Char?) : Bool
    !!char && (char.alphanumeric? || char.in?('_', '$', '.', '#', '@'))
  end

  private def primary(text : String) : Access::CNF
    return unresolved(text) unless call = text.match(CALL)
    name = call[1]
    args = call[2]?
    return unresolved(text) if args && !operands(args, "||", "or")
    if args.nil? || args.blank?
      case name
      when "permitAll"
        Access::CNF.new
      when "denyAll"
        [[Access::Atom.new(:deny)]]
      when "isAnonymous", "anonymous"
        [[Access::Atom.new(:anonymous)]]
      when "isAuthenticated", "isFullyAuthenticated", "authenticated", "fullyAuthenticated"
        [[Access::Atom.new(:authenticated)]]
      else
        unresolved(text)
      end
    else
      case name
      when "hasRole", "hasAnyRole"
        list(args, text) { |value| role_atom(value) }
      when "hasAuthority", "hasAnyAuthority"
        list(args, text) { |value| authority_atom(value) }
      when "access"
        (expression = literal(args)) ? expression(expression) : unresolved(text)
      else
        unresolved(text)
      end
    end
  end

  # One clause over the comma-separated values of `args`, each mapped by the
  # block; a non-literal value is an unresolved atom.
  private def list(args : String?, source : String, & : String -> Access::Atom) : Access::CNF
    return unresolved(source) unless args
    inner = args.sub(VALUE_KEY, "").strip
    inner = inner[1...-1] if (inner.starts_with?('{') && inner.ends_with?('}')) || (inner.starts_with?('[') && inner.ends_with?(']'))
    values = Noir::TopLevelSplit.split(inner, ',', Noir::TopLevelSplit::Rules.new(empties: Noir::TopLevelSplit::Empties::DropAll))
    return unresolved(source) if values.empty?
    atoms = [] of Access::Atom
    values.each do |value|
      if text = literal(value)
        atoms << yield text
      else
        atoms << Access::Atom.new(:unresolved, value)
      end
    end
    [atoms]
  end

  private def role_atom(value : String) : Access::Atom
    role = value.lchop("ROLE_")
    role == "ANONYMOUS" ? Access::Atom.new(:anonymous) : Access::Atom.new(:role, role)
  end

  private def authority_atom(value : String) : Access::Atom
    if value.starts_with?("ROLE_")
      role_atom(value)
    elsif value.starts_with?("SCOPE_")
      Access::Atom.new(:scope, value.lchop("SCOPE_"))
    else
      Access::Atom.new(:permission, value)
    end
  end

  # Spring Security 5 gives `IS_AUTHENTICATED_*` a meaning of its own; 6
  # compares it as a literal authority nobody holds.
  private def secured_atom(value : String) : Access::Atom
    value.starts_with?("IS_AUTHENTICATED_") ? Access::Atom.new(:unresolved, value) : authority_atom(value)
  end

  private def literal(text : String) : String?
    return unless found = text.match(LITERAL)
    (found[1]? || found[2]?).to_s.gsub(/\\(.)/, "\\1")
  end

  private def unresolved(fragment : String) : Access::CNF
    [[Access::Atom.new(:unresolved, fragment)]]
  end
end
