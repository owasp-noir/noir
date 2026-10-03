module Noir
  # Blanks `//` line comments and `/* */` block comments in C-family source
  # with spaces, keeping every newline so line numbers and offsets in the
  # cleaned copy match the original. String literals are tracked so a `//`
  # or `/*` inside one (`"http://x//y"`) is never read as a comment opener.
  module CComments
    # `quotes` open a string literal in which a backslash escapes the next
    # char; `raw_quotes` open one that takes no escapes (Go's backtick).
    #
    # An unterminated `/*` is blanked through the end of the text. With
    # `leak_unterminated_tail` the scan instead stops one char early and the
    # text's final character passes through verbatim — the Java/Go strippers
    # always behaved that way, and their output is kept byte-identical.
    def self.strip(text : String,
                   quotes : String = %("'),
                   raw_quotes : String = "",
                   leak_unterminated_tail : Bool = false) : String
      return text unless text.includes?("//") || text.includes?("/*")

      result = String::Builder.new
      chars = text.chars
      i = 0
      in_string = false
      string_quote = '\0'

      while i < chars.size
        c = chars[i]

        if in_string
          if c == '\\' && i + 1 < chars.size && !raw_quotes.includes?(string_quote)
            result << c << chars[i + 1]
            i += 2
            next
          end
          in_string = false if c == string_quote
          result << c
          i += 1
          next
        end

        if quotes.includes?(c) || raw_quotes.includes?(c)
          in_string = true
          string_quote = c
          result << c
          i += 1
          next
        end

        if c == '/' && i + 1 < chars.size && chars[i + 1] == '/'
          while i < chars.size && chars[i] != '\n'
            result << ' '
            i += 1
          end
          next
        end

        if c == '/' && i + 1 < chars.size && chars[i + 1] == '*'
          result << "  "
          i += 2
          limit = leak_unterminated_tail ? chars.size - 1 : chars.size
          while i < limit && !(i + 1 < chars.size && chars[i] == '*' && chars[i + 1] == '/')
            result << (chars[i] == '\n' ? '\n' : ' ')
            i += 1
          end
          if i + 1 < chars.size
            result << "  "
            i += 2
          end
          next
        end

        result << c
        i += 1
      end

      result.to_s
    end
  end
end
