module Analyzer::Clojure
  # Shared helpers for the Clojure framework analyzers (CLI, Compojure,
  # Pedestal, Reitit, Ring). Every one of them walks s-expressions the same
  # way, so the scanning primitives live here instead of being copied per
  # analyzer.
  #
  # All four operate on byte offsets into the raw source (`byte_at`), never on
  # character indices, so the offsets they return stay usable with
  # `String#byte_slice` on sources containing non-ASCII text.
  module Helper
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

    # Find the offset of the delimiter closing the one at `index`, skipping
    # over comments and string literals so a `)` inside `";)"` never closes a
    # form. Returns `index` unchanged when no match is found.
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

    # 1-based line number of a byte offset.
    def line_number_for(source : String, index : Int32) : Int32
      source.byte_slice(0, index).count('\n') + 1
    end
  end
end
