require "../minilexers/php_lexer"

module Noir
  # Public members of a PHP class body, read off a `PhpLexer`'s masked text
  # (strings and comments blanked), so a `public $x` or `{` inside a string
  # or comment cannot fake a member or end the body early. Method bodies are
  # skipped whole, so members of an anonymous class inside a method are not
  # reported as the outer class's.
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

    MEMBER_RE    = /(?:\b(static|readonly)\s+)?\bpublic\s+((?:(?:static|final|abstract)\s+)*)(?:function\s+&?\s*([A-Za-z_]\w*)\s*\(|(?!function\b|const\b)(readonly\s+)?(?:\??[\w\\]+(?:\s*\|\s*\??[\w\\]+)*\s+)?\$([A-Za-z_]\w*))/
    ARG_RE       = /\$([A-Za-z_]\w*)/
    LIST_NAME_RE = /\G,\s*\$([A-Za-z_]\w*)/
    CLASS_RE     = /(?<!::)\bclass\b[^{;]*\{/

    # `{open brace index, close brace index}` of every top-level class body
    # in the file, in source order. Anonymous classes nested in a method are
    # skipped: their methods are not the outer class's.
    def self.class_bodies(lexer : PhpLexer, masked : String) : Array(Tuple(Int32, Int32))
      bodies = [] of Tuple(Int32, Int32)
      pos = 0
      while m = CLASS_RE.match(masked, pos)
        open = m.end(0) - 1
        close = lexer.matching_delimiter(open)
        break unless close
        bodies << {open, close}
        pos = close + 1
      end
      bodies
    end

    def self.each(lexer : PhpLexer, masked : String, open : Int32, close : Int32, & : Member ->)
      chars = lexer.masked
      code = lexer.without_comments.chars
      pos = open + 1
      line = 1
      counted = 0
      while (m = MEMBER_RE.match(masked, pos)) && (start = m.begin(0)) < close
        prelude = code[prelude_start(chars, start, open)...start].join
        (counted...start).each { |i| line += 1 if chars[i] == '\n' }
        counted = start
        static = m[1]? == "static" || m[2].includes?("static")
        if name = m[3]?
          paren = m.end(0) - 1
          paren_close = lexer.matching_delimiter(paren) || break
          args = chars[(paren + 1)...paren_close].join.scan(ARG_RE).map(&.[1])
          yield Member.new(name, true, static, false, args, prelude, line)
          body = paren_close + 1
          while body < close && chars[body] != '{' && chars[body] != ';'
            body += 1
          end
          break if body >= close
          pos = chars[body] == '{' ? (lexer.matching_delimiter(body) || break) + 1 : body + 1
        else
          readonly = m[1]? == "readonly" || !m[4]?.nil?
          yield Member.new(m[5], false, static, readonly, [] of String, prelude, line)
          # `public $a, $b = [1, 2];` declares every name in the list. Stop at
          # the `;`, or at a property-hook `{` (PHP 8.4).
          pos = m.end(0)
          depth = 0
          while pos < close
            c = chars[pos]
            break if c == '{' || (c == ';' && depth <= 0)
            if c == '(' || c == '['
              depth += 1
            elsif c == ')' || c == ']'
              depth -= 1
            elsif c == ',' && depth == 0 && (n = LIST_NAME_RE.match(masked, pos))
              yield Member.new(n[1], false, static, readonly, [] of String, prelude, line)
            end
            pos += 1
          end
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
