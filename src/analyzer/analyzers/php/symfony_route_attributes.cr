require "../../../minilexers/php_lexer"

# Symfony's route attribute/annotation grammar (`#[Route(...)]`,
# `@Route(...)`), shared by `Analyzer::Php::Symfony` and
# `Analyzer::Php::Drupal`, whose controllers use the same attribute.
module Analyzer::Php::SymfonyRouteAttributes
  # The options Symfony's Route attribute/annotation takes besides its path.
  SYMFONY_ROUTE_KEYS = %w[name methods requirements defaults condition host schemes env priority locale format utf8 stateless options alias]

  # A `@Route(...)` annotation or `#[Route(...)]` attribute: where it
  # starts and ends, and the text between its parentheses.
  record RouteAttr, start : Int32, stop : Int32, args : String

  # Every route annotation/attribute in `content`, its parentheses matched
  # past strings (`condition="request.isXmlHttpRequest()"`). One whose
  # parentheses do not balance is skipped. An attribute is code, so one
  # written inside a string literal is text; an annotation lives in a
  # docblock and has its ` * ` line prefixes dropped.
  private def route_attributes(content : String, lexer : Noir::PhpLexer) : Array(RouteAttr)
    attrs = [] of RouteAttr
    content.scan(/(@|#\[)Route\s*\(/) do |m|
      start = m.begin(0)
      open = m.end(0) - 1
      if m[1] == "#["
        next unless lexer.in_code?(start) && (close = lexer.matching_delimiter(open))
        attrs << RouteAttr.new(start, close + 1, content[open + 1...close])
      else
        block = content[open...(content.index("*/", open) || content.size)]
        next unless close = Noir::PhpLexer.new(block, php_mode: true).matching_delimiter(0)
        attrs << RouteAttr.new(start, open + close + 1, block[1...close].gsub(/\n\s*\*/, "\n"))
      end
    end
    attrs
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

  private def extract_methods_from_symfony_context(context : String) : Array(String)
    methods = [] of String

    if match = context.match(/methods\s*[:=]\s*\[([^\]]+)\]/m)
      methods.concat(extract_method_tokens(match[1]))
    elsif match = context.match(/methods\s*=\s*\{([^}]+)\}/m)
      methods.concat(extract_method_tokens(match[1]))
    elsif match = context.match(/methods\s*[:=]\s*['"]([^'"]+)['"]/)
      methods << match[1].upcase
    elsif match = context.match(/methods\s*[:=]\s*(?:[\w\\]+::)?METHOD_(\w+)/i)
      methods << match[1].upcase
    end

    methods.uniq
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
end
