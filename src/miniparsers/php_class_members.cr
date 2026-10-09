require "../minilexers/php_lexer"

module Noir
  # Public members of a PHP class body, read off a `PhpLexer`'s masked text
  # (strings and comments blanked), so a `public $x` or `{` inside a string
  # or comment cannot fake a member or end the body early. Method bodies are
  # skipped whole, so members of an anonymous class inside a method are not
  # reported as the outer class's.
  #
  # `prelude` is the original source between the previous member and this
  # one: attributes (`#[Locked]`, `#[ApiRoute(...)]`) and the docblock, which
  # is where annotation-style markers (`@PublicPage`) live.
  module PhpClassMembers
    record Member,
      name : String,
      method : Bool,
      static : Bool,
      readonly : Bool,
      args : Array(String),
      prelude : String,
      line : Int32

    MEMBER_RE = /\bpublic\s+(static\s+)?(?:function\s+&?\s*([A-Za-z_]\w*)\s*\(|(?!function\b|const\b)(readonly\s+)?(?:\??[\w\\]+(?:\s*\|\s*\??[\w\\]+)*\s+)?\$([A-Za-z_]\w*))/
    ARG_RE    = /\$([A-Za-z_]\w*)/
    CLASS_RE  = /(?<!::)\bclass\b[^{;]*\{/

    # `{open brace index, close brace index}` of every class body in the
    # file (named or anonymous), in source order.
    def self.class_bodies(lexer : PhpLexer, masked : String) : Array(Tuple(Int32, Int32))
      bodies = [] of Tuple(Int32, Int32)
      pos = 0
      while m = CLASS_RE.match(masked, pos)
        open = m.end(0) - 1
        close = lexer.matching_delimiter(open)
        break unless close
        bodies << {open, close}
        pos = open + 1
      end
      bodies
    end

    def self.each(lexer : PhpLexer, masked : String, open : Int32, close : Int32, & : Member ->)
      chars = lexer.masked
      pos = open + 1
      line = 1
      counted = 0
      while (m = MEMBER_RE.match(masked, pos)) && (start = m.begin(0)) < close
        prelude = lexer.source(prelude_start(chars, start, open)...start)
        (counted...start).each { |i| line += 1 if chars[i] == '\n' }
        counted = start
        if name = m[2]?
          paren = m.end(0) - 1
          paren_close = lexer.matching_delimiter(paren) || break
          args = chars[(paren + 1)...paren_close].join.scan(ARG_RE).map(&.[1])
          yield Member.new(name, true, !m[1]?.nil?, false, args, prelude, line)
          body = paren_close + 1
          while body < close && chars[body] != '{' && chars[body] != ';'
            body += 1
          end
          break if body >= close
          pos = chars[body] == '{' ? (lexer.matching_delimiter(body) || break) + 1 : body + 1
        else
          yield Member.new(m[4], false, !m[1]?.nil?, !m[3]?.nil?, [] of String, prelude, line)
          pos = m.end(0)
        end
      end
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
