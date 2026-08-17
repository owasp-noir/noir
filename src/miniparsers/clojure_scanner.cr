module Noir
  # Low-level Clojure reader primitives, shared by the callee extractor in this
  # directory and by the Clojure framework analyzers — `Analyzer::Clojure::Helper`
  # is a thin delegation layer over this module, so the two never drift again.
  #
  # Every offset here is a *byte* offset into the raw source (`byte_at`), never a
  # character index, so the values stay usable with `String#byte_slice` on sources
  # containing non-ASCII text.
  module ClojureScanner
    extend self

    # Advance past a `;` line comment, stopping on the newline that ends it.
    def skip_comment(source : String, index : Int32, limit : Int32) : Int32
      i = index
      while i < limit && source.byte_at(i).unsafe_chr != '\n'
        i += 1
      end
      i
    end

    # Advance from the opening `"` of a string literal to its closing quote,
    # honouring `\` escapes. Returns the last in-range offset when the literal
    # is unterminated so callers still make progress.
    def skip_string(source : String, index : Int32, limit : Int32) : Int32
      i = index + 1
      escaping = false

      while i < limit
        char = source.byte_at(i).unsafe_chr
        if escaping
          escaping = false
        elsif char == '\\'
          escaping = true
        elsif char == '"'
          return i
        end
        i += 1
      end

      limit - 1
    end

    # Advance from the `\` that opens a character literal to the literal's last
    # byte (the same "last byte consumed" contract as `skip_string`).
    #
    # Clojure character literals are `\a`, `\"`, `\(`, `\\`, `\;` (a single
    # character, reader-significant ones included), the named forms `\newline`,
    # `\space`, `\tab`, `\formfeed`, `\backspace` and `\return`, `\uXXXX` and
    # `\oNNN`. Without this, `\"` opens a string that runs to the next quote in
    # the file and `\(` counts as a real open paren, so depth accounting — and
    # with it every route below the literal — collapses.
    def skip_char_literal(source : String, index : Int32, limit : Int32) : Int32
      # A trailing backslash at the very end of the range has nothing to consume.
      return index if index + 1 >= limit

      # The character right after the backslash always belongs to the literal,
      # whatever it is: in `\\` the escaped-looking backslash *is* the character
      # and the literal ends there, and `\;` is a semicolon, not a comment.
      last = index + 1

      # Named, unicode and octal literals run longer than one character. Take the
      # whole token so `\newline` cannot leave `ewline` behind to be read as a
      # symbol.
      if source.byte_at(last).unsafe_chr.ascii_alphanumeric?
        while last + 1 < limit && source.byte_at(last + 1).unsafe_chr.ascii_alphanumeric?
          last += 1
        end
      end

      last
    end

    # Find the offset of the delimiter closing the one at `index`, skipping over
    # comments, string literals and character literals so a `)` inside `";)"` or
    # a `\(` never moves the depth counter. Returns `index` unchanged when no
    # match is found.
    def find_matching_delimiter(source : String, index : Int32, open_char : Char, close_char : Char, limit : Int32) : Int32
      depth = 0
      i = index

      while i < limit
        char = source.byte_at(i).unsafe_chr
        case char
        when ';'
          i = skip_comment(source, i, limit)
        when '"'
          i = skip_string(source, i, limit)
        when '\\'
          i = skip_char_literal(source, i, limit)
        when open_char
          depth += 1
        when close_char
          depth -= 1
          return i if depth == 0
        end
        i += 1
      end

      index
    end

    # Line number of a byte offset, counted from `start_line` (1-based by
    # default, matching a whole-file offset).
    def line_number_for(source : String, index : Int32, start_line : Int32 = 1) : Int32
      start_line + source.to_slice[0, index].count('\n'.ord.to_u8)
    end
  end
end
