require "./php_block_parser"

module Noir
  # Public members of a PHP class body, as `PhpBlockParser` reads them off
  # the masked text (strings and comments blanked), so a `public $x` or `{`
  # inside a string or comment cannot fake a member or end the body early.
  # Members of an anonymous class inside a method are that class's, not the
  # outer one's.
  #
  # `prelude` is the source between the previous member and this one with
  # `//`, `#` and `/* */` comments blanked: attributes (`#[Locked]`,
  # `#[ApiRoute(...)]`) and the docblock, which is where annotation-style
  # markers (`@PublicPage`) live. A commented-out attribute is not one.
  module PhpClassMembers
    record Member,
      name : String,
      method : Bool,
      static : Bool,
      readonly : Bool,
      args : Array(String),
      prelude : String,
      line : Int32

    ARG_RE = /\$([A-Za-z_]\w*)/

    # The members of the class whose body opens at the `{` at `open`.
    def self.each(parser : PhpBlockParser, open : Int32, & : Member ->) : Nil
      klass = parser.path(open).reverse_each.find { |node| node.kind.class? && node.body.begin == open + 1 }
      each(parser, klass) { |member| yield member } if klass
    end

    def self.each(parser : PhpBlockParser, klass : PhpBlockParser::Node, & : Member ->) : Nil
      chars = parser.lexer.masked
      code = parser.lexer.without_comments.chars
      line = 1
      counted = 0
      klass.children.each do |node|
        next unless node.modifiers.includes?("public")
        start = node.start
        prelude = code[prelude_start(chars, start, klass.body.begin - 1)...start].join
        (counted...start).each { |i| line += 1 if chars[i] == '\n' }
        counted = start
        static = node.modifiers.includes?("static")
        if node.kind.method?
          args = node.head.try { |head| chars[head].join.scan(ARG_RE).map(&.[1]) } || [] of String
          yield Member.new(node.name || "", true, static, false, args, prelude, line)
        elsif node.kind.property?
          readonly = node.modifiers.includes?("readonly")
          property_names(chars, node.body).each do |name|
            yield Member.new(name, false, static, readonly, [] of String, prelude, line)
          end
        end
      end
    end

    # `public $a, $b = [1, 2];` declares every name in the list; a property
    # hook body (PHP 8.4 `{ get => ... }`) declares none.
    private def self.property_names(chars : Array(Char), range : Range(Int32, Int32)) : Array(String)
      names = [] of String
      depth = 0
      expect = true
      pos = range.begin
      while pos < range.end
        c = chars[pos]
        break if c == '{' && depth == 0
        if c == '(' || c == '['
          depth += 1
        elsif c == ')' || c == ']'
          depth -= 1
        elsif c == ',' && depth == 0
          expect = true
        elsif c == '$' && depth == 0 && expect
          stop = pos + 1
          while stop < range.end && (chars[stop] == '_' || chars[stop].ascii_alphanumeric?)
            stop += 1
          end
          names << chars[(pos + 1)...stop].join if stop > pos + 1
          expect = false
          pos = stop
          next
        end
        pos += 1
      end
      names
    end

    # Back to the end of the previous member (`;` / `}`) or the class's `{`.
    private def self.prelude_start(chars : Array(Char), start : Int32, open : Int32) : Int32
      i = start - 1
      while i > open
        c = chars[i]
        return i + 1 if c == ';' || c == '}' || c == '{'
        i -= 1
      end
      open + 1
    end
  end
end
