module Noir
  # Structural helpers shared by the hand-rolled masking lexers
  # (`Noir::PhpLexer`, `Noir::CSharpLexer`, `Noir::ScalaLexer`).
  #
  # Each of those lexers exists for the same reason: the analyzers they feed
  # used to count `{`/`}`/`(`/`)`/`;` per line with no string awareness, so a
  # single delimiter inside a string literal, a comment or a heredoc body
  # truncated a method block (dropping callees), made a signature run away
  # (dropping parameters), or leaked route-shaped text as a phantom endpoint.
  # Each lexer therefore makes ONE linear pass that blanks every non-code region
  # to spaces — newlines preserved, character length unchanged — into `@masked`,
  # and records each blanked region in `@spans`.
  #
  # The language-specific part is that masking pass (PHP heredocs and `#[…]`
  # attributes, the C# string zoo, Scala's nested block comments and
  # triple-quoted strings). Everything below is what is left once masking is
  # done: plain depth counters and span lookups over `@masked`/`@spans` with no
  # string-state bookkeeping of their own, and therefore language-agnostic.
  #
  # An includer must declare `@masked`, `@size`, `@spans` and `@skip_ranges`.
  # They are declared here so the contract is enforced at compile time rather
  # than restated (and potentially drifting) in each lexer.
  module MaskedLexer
    # Code with strings, comments and any other non-code region (PHP heredoc
    # bodies, Scala triple-quoted strings, …) blanked to spaces. Same character
    # length as the source and newlines preserved, so line/offset math against
    # the original content stays valid.
    getter masked : Array(Char)

    # Source length in characters. The source is materialised once into an
    # `Array(Char)` for O(1) indexing, so scanning stays O(n) on multi-byte
    # (e.g. CJK-commented) input instead of the O(n^2) that `String#[](Int)`
    # would cost.
    @size : Int32

    # Recorded non-code regions as {kind, start, end_exclusive}. Used for
    # `skip_ranges`, `in_code?`, and to splice string/comment spans into each
    # lexer's token stream.
    @spans : Array(Tuple(Symbol, Int32, Int32))

    # Memo for `skip_ranges`.
    @skip_ranges : Array(Range(Int32, Int32))?

    # Index of the delimiter that closes the `(`/`[`/`{` at `open_pos`, or nil.
    # Counts only the matching pair type, which is correct for balanced code and
    # mirrors the per-analyzer scanners this replaces (e.g. PHP's
    # `find_matching_php_close_brace`).
    def matching_delimiter(open_pos : Int32) : Int32?
      return unless 0 <= open_pos && open_pos < @size
      open = @masked[open_pos]
      close = case open
              when '(' then ')'
              when '[' then ']'
              when '{' then '}'
              else          return
              end
      depth = 0
      i = open_pos
      while i < @size
        c = @masked[i]
        if c == open
          depth += 1
        elsif c == close
          depth -= 1
          return i if depth == 0
        end
        i += 1
      end
      nil
    end

    # Index just after the top-level `;` at or after `start_pos`, or the source
    # size when none is found. Mirrors PHP's `find_php_statement_end`.
    def statement_end(start_pos : Int32) : Int32
      paren = 0
      bracket = 0
      brace = 0
      i = start_pos < 0 ? 0 : start_pos
      while i < @size
        case @masked[i]
        when '(' then paren += 1
        when ')' then paren -= 1 if paren > 0
        when '[' then bracket += 1
        when ']' then bracket -= 1 if bracket > 0
        when '{' then brace += 1
        when '}' then brace -= 1 if brace > 0
        when ';'
          return i + 1 if paren == 0 && bracket == 0 && brace == 0
        end
        i += 1
      end
      @size
    end

    # Character ranges occupied by the non-code regions: strings, comments and
    # whatever else the includer masks (PHP heredoc/nowdoc bodies, …).
    def skip_ranges : Array(Range(Int32, Int32))
      @skip_ranges ||= @spans.map { |(_, s, e)| (s..e - 1) }
    end

    def in_code?(pos : Int32) : Bool
      return false unless 0 <= pos && pos < @size
      @spans.none? { |(_, s, e)| s <= pos && pos < e }
    end

    # Identifier classification is deliberately permissive about >= 0x80: every
    # one of these languages allows non-ASCII identifiers, and the lexers must
    # not split a CJK or accented name into fragments.
    private def ident_char?(c : Char) : Bool
      c == '_' || c.ascii_alphanumeric? || c.ord >= 0x80
    end

    private def ident_start?(c : Char) : Bool
      c == '_' || c.ascii_letter? || c.ord >= 0x80
    end
  end
end
