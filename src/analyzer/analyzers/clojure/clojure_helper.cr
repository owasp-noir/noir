require "../../../miniparsers/clojure_scanner"

module Analyzer::Clojure
  # Shared helpers for the Clojure framework analyzers (CLI, Compojure,
  # Pedestal, Reitit, Ring). Every one of them walks s-expressions the same
  # way, so the scanning primitives live here instead of being copied per
  # analyzer.
  #
  # The primitives themselves belong to the parser layer, so this is only a
  # thin adapter over `Noir::ClojureScanner` (`src/miniparsers/`). Keeping a
  # second copy here is what let a reader bug — `\(` counted as a real open
  # paren — live on in the analyzers after it was fixed in the miniparser.
  #
  # All of them operate on byte offsets into the raw source (`byte_at`), never
  # on character indices, so the offsets they return stay usable with
  # `String#byte_slice` on sources containing non-ASCII text.
  module Helper
    extend self

    # Advance past a `;` line comment, stopping on the newline that ends it.
    def skip_comment(source : String, index : Int32, limit : Int32) : Int32
      Noir::ClojureScanner.skip_comment(source, index, limit)
    end

    # Advance from the opening `"` of a string literal to its closing quote,
    # honouring `\` escapes. Returns the last in-range offset when the literal
    # is unterminated so callers still make progress.
    def skip_string(source : String, index : Int32, limit : Int32) : Int32
      Noir::ClojureScanner.skip_string(source, index, limit)
    end

    # Advance from the `\` opening a character literal (`\a`, `\"`, `\(`,
    # `\newline`, `\uXXXX`, …) to the literal's last byte.
    def skip_char_literal(source : String, index : Int32, limit : Int32) : Int32
      Noir::ClojureScanner.skip_char_literal(source, index, limit)
    end

    # Find the offset of the delimiter closing the one at `index`, skipping
    # over comments, strings and character literals so a `)` inside `";)"` or a
    # `\(` never closes a form. Returns `index` unchanged when no match is
    # found.
    def find_matching_delimiter(source : String, index : Int32, open_char : Char, close_char : Char, limit : Int32) : Int32
      Noir::ClojureScanner.find_matching_delimiter(source, index, open_char, close_char, limit)
    end

    # 1-based line number of a byte offset.
    def line_number_for(source : String, index : Int32) : Int32
      Noir::ClojureScanner.line_number_for(source, index)
    end
  end
end
