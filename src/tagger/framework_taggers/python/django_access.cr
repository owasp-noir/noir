require "../../../models/access"
require "../../../utils/top_level_split"
require "../../../utils/js_literal_scanner"

# Reads Django's and Django REST framework's authorization vocabulary into a
# requirement: the auth decorators, the auth mixins' attributes and DRF
# permission class expressions.
module DjangoAccess
  extend self

  LITERAL = /\A\s*[rRuU]?(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')\s*\z/
  CALL    = /\A\s*@?\s*([A-Za-z_][\w.]*)\s*/
  SAFE    = %w[GET HEAD OPTIONS]
  UNSAFE  = %w[POST PUT PATCH DELETE]
  ARGS    = Noir::TopLevelSplit::Rules.new(
    nest: Noir::TopLevelSplit::Nest::Paren | Noir::TopLevelSplit::Nest::Bracket | Noir::TopLevelSplit::Nest::Brace,
    quotes: "\"'", escape: Noir::TopLevelSplit::Escape::InQuotes, strip: true,
    empties: Noir::TopLevelSplit::Empties::DropAll)

  # Django has no role model: the admin and `staff_member_required` test
  # `is_staff`, which no atom names.
  STAFF      = [[Access::Atom.new(:authenticated)], [Access::Atom.new(:unresolved, "is_staff")]]
  ADMIN_SITE = STAFF + [[Access::Atom.new(:unresolved, "ModelAdmin permissions")]]

  # `name(args)` at the start of `text` (`@permission_required('a.b')`,
  # `login_required(views.home)`): the dotted name, the text between the
  # parentheses (nil when there are none or they do not close), and the
  # call's own text.
  def call(text : String) : {String, String?, String}?
    found = text.match(CALL) || return
    name = found[1]
    rest = text[found.end..]
    return {name, nil, name} unless rest.starts_with?('(')
    # JavaScript quotes strings as Python does, which is all an argument
    # list needs.
    close = Noir::JSLiteralScanner.find_matching_paren(rest, 0) || return {name, nil, text.lines.first.strip.lchop('@')}
    {name, rest[1...close], "#{name}#{rest[0..close]}"}
  end

  # A Django auth decorator by its last name segment; nil for any other.
  # `user_passes_test` runs its test on `AnonymousUser` too, so it says
  # nothing about signing in.
  def decorator(name : String, args : String?, source : String) : Access::CNF?
    case name.rpartition('.')[2]
    when "login_required"        then [[Access::Atom.new(:authenticated)]]
    when "staff_member_required" then STAFF
    when "user_passes_test"      then unresolved(source)
    when "permission_required"
      value = args.try { |text| argument(text, "perm") }
      value ? permission_required(value) : [[Access::Atom.new(:authenticated)], [Access::Atom.new(:unresolved, source)]]
    end
  end

  # `has_perms` holds only when the user holds every listed permission, and
  # `AnonymousUser` holds none.
  def permission_required(value : String) : Access::CNF
    value = value.strip
    signed_in = [Access::Atom.new(:authenticated)]
    if perm = literal(value)
      return [signed_in, [Access::Atom.new(:permission, perm)]]
    end
    if (value.starts_with?('(') && value.ends_with?(')')) || (value.starts_with?('[') && value.ends_with?(']'))
      items = Noir::TopLevelSplit.split(value[1...-1], ',', ARGS)
      # An empty list asks for nothing, and `has_perms([])` holds for anyone.
      return unresolved(value) if items.empty?
      return [signed_in] + items.map { |item| [literal(item).try { |name| Access::Atom.new(:permission, name) } || Access::Atom.new(:unresolved, item)] }
    end
    [signed_in, [Access::Atom.new(:unresolved, value)]]
  end

  # The decorators `method_decorator(...)` applies: its first argument, a
  # single decorator or a list of them. Nil when the arguments are not read.
  def method_decorator_targets(args : String) : Array(String)?
    first = argument(args, "decorator") || return
    bracketed = (first.starts_with?('[') && first.ends_with?(']')) || (first.starts_with?('(') && first.ends_with?(')'))
    bracketed ? Noir::TopLevelSplit.split(first[1...-1], ',', ARGS) : [first]
  end

  # A DRF permission expression (`[IsAuthenticated, IsAdminUser]`,
  # `(IsAuthenticated | ReadOnly,)`, a settings list of dotted paths) for a
  # request of `method`. DRF checks every listed class and composes them
  # with `&`, `|` and `~`. Text that does not parse is one unresolved atom.
  def drf(text : String, method : String) : Access::CNF
    tokens = drf_tokens(text) || return unresolved(text.strip)
    parser = DrfParser.new(tokens, method)
    result = parser.list(nil)
    parser.done? ? result : unresolved(text.strip)
  rescue DrfParser::Error
    unresolved(text.strip)
  end

  def drf_class(name : String, source : String, method : String) : Access::CNF
    case name.rpartition('.')[2]
    when "AllowAny"        then Access::CNF.new
    when "IsAuthenticated" then [[Access::Atom.new(:authenticated)]]
    when "IsAdminUser"     then STAFF
    when "IsAuthenticatedOrReadOnly"
      read_only(method, [[Access::Atom.new(:authenticated)]], source)
    when "DjangoModelPermissionsOrAnonReadOnly"
      read_only(method, [[Access::Atom.new(:authenticated)], [Access::Atom.new(:unresolved, source)]], source)
    when "DjangoModelPermissions", "DjangoObjectPermissions"
      # Refuses `AnonymousUser`; which model permission it asks for depends
      # on the verb and the queryset.
      [[Access::Atom.new(:authenticated)], [Access::Atom.new(:unresolved, source)]]
    else
      unresolved(source)
    end
  end

  # Open for safe verbs; a verb noir does not know may be either.
  private def read_only(method : String, unsafe : Access::CNF, source : String) : Access::CNF
    verb = method.upcase
    return Access::CNF.new if SAFE.includes?(verb)
    UNSAFE.includes?(verb) ? unsafe : unresolved(source)
  end

  # A guard noir reports but does not read past its refusing an anonymous
  # caller: what `Access.of` reads off a tag with no requirement.
  def unread(description : String) : Access::CNF
    [[Access::Atom.new(:authenticated)], [Access::Atom.new(:unresolved, description)]]
  end

  # A requirement something unread can lift: each clause also holds when it does.
  def liftable(cnf : Access::CNF, fragment : String) : Access::CNF
    cnf.map { |atoms| (atoms + [Access::Atom.new(:unresolved, fragment)]).uniq }
  end

  def unresolved(fragment : String) : Access::CNF
    [[Access::Atom.new(:unresolved, fragment)]]
  end

  # The first positional argument, else the keyword `name`.
  private def argument(args : String, name : String) : String?
    parts = Noir::TopLevelSplit.split(args, ',', ARGS)
    parts.find { |part| !part.matches?(/\A\w+\s*=(?!=)/) } ||
      parts.find(&.matches?(/\A#{name}\s*=(?!=)/)).try(&.partition('=')[2].strip)
  end

  private def literal(text : String) : String?
    found = text.match(LITERAL) || return
    (found[1]? || found[2]?).to_s.gsub(/\\(.)/, "\\1")
  end

  private record Token, text : String, name : String?

  DRF_TOKEN = /\G\s*(?:"([^"\\\n]*)"|'([^'\\\n]*)'|([A-Za-z_][\w.]*)|([|&~(),\[\]]))/

  # Names (settings quote dotted paths) and operators; nil on anything else.
  private def drf_tokens(text : String) : Array(Token)?
    tokens = [] of Token
    pos = 0
    while pos < text.size
      break if text[pos..].blank?
      found = text.match(DRF_TOKEN, pos) || return
      pos = found.end
      if name = found[1]? || found[2]? || found[3]?
        tokens << Token.new(found[0].strip, name)
      else
        tokens << Token.new(found[4], nil)
      end
    end
    tokens
  end

  # list := expr (',' expr)* [','] ; expr := term ('|' term)* ;
  # term := unary ('&' unary)* ; unary := '~' unary | '(' list ')' |
  # '[' list ']' | NAME ['(' ... ')'].
  private class DrfParser
    class Error < Exception
    end

    def initialize(@tokens : Array(Token), @method : String)
      @pos = 0
    end

    def done? : Bool
      @pos == @tokens.size
    end

    def list(close : String?) : Access::CNF
      result = Access::CNF.new
      until peek.nil? || peek == close
        result = Access.both(result, expr)
        break unless peek == ","
        @pos += 1
      end
      result
    end

    private def expr : Access::CNF
      result = term
      while peek == "|"
        @pos += 1
        result = Access.either(result, term)
      end
      result
    end

    private def term : Access::CNF
      result = unary
      while peek == "&"
        @pos += 1
        result = Access.both(result, unary)
      end
      result
    end

    private def unary : Access::CNF
      start = @pos
      token = @tokens[@pos]? || raise Error.new
      @pos += 1
      if name = token.name
        skip_arguments
        return DjangoAccess.drf_class(name, source(start), @method)
      end
      case token.text
      when "~"
        unary
        DjangoAccess.unresolved(source(start))
      when "(", "["
        close = token.text == "(" ? ")" : "]"
        inner = list(close)
        raise Error.new unless peek == close
        @pos += 1
        inner
      else
        raise Error.new
      end
    end

    # An instance (`HasScope("read")`): its arguments are not the expression.
    private def skip_arguments
      return unless peek == "("
      depth = 0
      while token = @tokens[@pos]?
        depth += 1 if token.text == "("
        depth -= 1 if token.text == ")"
        @pos += 1
        return if depth == 0
      end
      raise Error.new
    end

    private def source(start : Int32) : String
      @tokens[start...@pos].map(&.text).join(" ").gsub(/\s*([().\[\],])\s*/, "\\1").gsub("~ ", "~")
    end

    private def peek : String?
      token = @tokens[@pos]? || return
      token.name ? "NAME" : token.text
    end
  end
end
