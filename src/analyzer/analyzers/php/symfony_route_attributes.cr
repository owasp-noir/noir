require "../../../miniparsers/php_block_parser"

# Symfony's route attribute/annotation grammar (`#[Route(...)]`,
# `@Route(...)`), shared by `Analyzer::Php::Symfony` and
# `Analyzer::Php::Drupal`, whose controllers use the same attribute.
module Analyzer::Php::SymfonyRouteAttributes
  # The options Symfony's Route attribute/annotation takes besides its path.
  SYMFONY_ROUTE_KEYS = %w[name methods requirements defaults condition host schemes env priority locale format utf8 stateless options alias]

  # Packages whose `Route` is Symfony's (or extends it).
  SYMFONY_ROUTE_NAMESPACES = {"Symfony\\", "FOS\\RestBundle\\", "Sensio\\Bundle\\FrameworkExtraBundle\\"}

  # A `@Route(...)` annotation or `#[Route(...)]` attribute: where it
  # starts and ends, the text between its parentheses, and for an
  # attribute whether it sits on a class (nil for an annotation, which is
  # judged by the text after it).
  record RouteAttr, start : Int32, stop : Int32, args : String, on_class : Bool? = nil

  # Every route annotation/attribute in `content` (the parser's source with
  # comments blanked), in source order. An attribute is what the parser
  # read: one inside a group (`#[IsGranted('X'), Route('/a')]`) or written
  # fully qualified counts, one inside a string or comment does not. An
  # annotation lives in a docblock and has its ` * ` line prefixes dropped;
  # one whose parentheses do not balance is skipped.
  private def route_attributes(content : String, parser : Noir::PhpBlockParser) : Array(RouteAttr)
    attrs = [] of RouteAttr
    targets = {} of Int32 => Bool
    parser.each_node { |node| node.attributes.each { |attribute| targets[attribute.start] = node.kind.class? } }
    parser.attributes.each do |attribute|
      next unless route_attribute?(attribute.name) && (args = attribute.args)
      stop = args.end + 1
      on_class = targets.has_key?(attribute.start) ? targets[attribute.start] : route_applies_to_class?(content, stop)
      attrs << RouteAttr.new(attribute.start, stop, content[args], on_class)
    end
    content.scan(/@Route\s*\(/) do |m|
      open = m.end(0) - 1
      block = content[open...(content.index("*/", open) || content.size)]
      next unless close = Noir::PhpLexer.new(block, php_mode: true).matching_delimiter(0)
      attrs << RouteAttr.new(m.begin(0), open + close + 1, block[1...close].gsub(/\n\s*\*/, "\n"))
    end
    attrs.sort_by!(&.start)
  end

  # `Route`, or Symfony's (FOSRest's, Sensio's) written fully qualified.
  private def route_attribute?(name : String) : Bool
    return true if name == "Route"
    name.ends_with?("\\Route") && SYMFONY_ROUTE_NAMESPACES.any? { |ns| name.lchop('\\').starts_with?(ns) }
  end

  # The top-level comma-separated arguments of an argument list.
  private def split_php_args(args : String) : Array(String)
    lexer = Noir::PhpLexer.new(args, php_mode: true)
    parts = [] of String
    pos = 0
    while pos < args.size
      stop = lexer.expression_end(pos)
      part = args[pos...stop].strip
      parts << part unless part.empty?
      pos = stop + 1
    end
    parts
  end

  # {named arguments, positional arguments} of an attribute/annotation
  # argument list (`name: 'x'` / `name="x"`; `Foo::BAR` is positional).
  private def attribute_args(args : String) : Tuple(Hash(String, String), Array(String))
    named = {} of String => String
    positional = [] of String
    split_php_args(args).each do |arg|
      if m = arg.match(/\A(\w+)\s*(?::(?!:)|=(?![=>]))\s*(.*)\z/m)
        named[m[1]] = m[2]
      else
        positional << arg
      end
    end
    {named, positional}
  end

  # The value of a single-quoted or double-quoted string literal without
  # interpolation or escapes, else nil.
  private def php_literal(expr : String) : String?
    return unless m = expr.match(/\A(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\$]|\\.)*)")\z/m)
    m[1]?.try(&.gsub("\\'", "'").gsub("\\\\", "\\")) || m[2]?
  end

  # The path a route attribute/annotation declares: its `path` (or the
  # annotation's `value`) argument, else its first positional argument,
  # when that is a string literal. A route of named arguments that are all
  # Symfony Route options and no path (`#[Route(methods: ['POST'], name:
  # 'x')]`) routes its class prefix itself, so "". A path given by a
  # constant or an expression (`self::LIST`) is nil: unknown, not "".
  private def extract_symfony_route_path(args : String) : String?
    named, positional = attribute_args(args)
    if expr = named["path"]? || named["value"]? || positional.first?
      return php_literal(expr)
    end
    "" if named.each_key.all? { |key| SYMFONY_ROUTE_KEYS.includes?(key) }
  end

  # The verbs of the `methods` argument: a list (`['GET']`, `{"GET"}`), a
  # string, or `Request::METHOD_*` constants. Only the argument itself is
  # read, so a `condition` string mentioning `methods: [...]` is not.
  private def extract_methods_from_symfony_context(context : String) : Array(String)
    value = attribute_args(context)[0]["methods"]? || return [] of String
    extract_method_tokens(value).uniq
  end

  # Methods inside a `methods: [...]` / `={...}` list — either string
  # literals (`'POST'`) or Symfony's `Request::METHOD_POST` constants (used
  # heavily by Shopware), which the string scan alone would have missed and
  # silently defaulted to GET.
  private def extract_method_tokens(list : String) : Array(String)
    tokens = [] of String
    list.scan(/['"]([^'"]+)['"]/) { |m| tokens << m[1].upcase }
    list.scan(/METHOD_(\w+)/i) { |m| tokens << m[1].upcase }
    tokens
  end

  # The next class or method declaration at or after `pos`. `class:` named
  # arguments and `Foo::class` in the attributes between are neither.
  private def next_declaration(content : String, pos : Int32) : Regex::MatchData?
    content.match(/(?<!::)\b(class\s+\w|function\b)/m, pos)
  end

  # Whether the attribute ending at `route_end` sits on a class.
  private def route_applies_to_class?(content : String, route_end : Int32) : Bool
    !!next_declaration(content, route_end).try(&.[1].starts_with?("class"))
  end

  private def route_applies_to_class?(content : String, attr : RouteAttr) : Bool
    attr.on_class.nil? ? route_applies_to_class?(content, attr.stop) : attr.on_class == true
  end
end
