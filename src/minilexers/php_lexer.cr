module Noir
  # A single token produced by `PhpLexer#tokens`. `start`/`end` are
  # character indices into the original source (`end` exclusive); `line`
  # is the 1-based line of `start`.
  struct PhpToken
    getter kind : Symbol
    getter value : String
    getter start : Int32
    getter end : Int32
    getter line : Int32

    def initialize(@kind : Symbol, @value : String, @start : Int32, @end : Int32, @line : Int32)
    end

    def to_s(io : IO) : Nil
      io << @kind << '(' << @value << ')'
    end
  end

  # PhpLexer is a hand-rolled structural lexer for PHP source. It exists to
  # replace the per-analyzer character state machines that every PHP analyzer
  # re-implements (balanced-brace matching, statement-end scanning, string/
  # comment skip ranges) with a single shared pass that is:
  #
  #   * heredoc/nowdoc aware — `<<<EOT … EOT` / `<<<'EOT' … EOT` bodies are
  #     masked, so route-shaped text or stray `{};` inside a heredoc can no
  #     longer leak as a false endpoint or corrupt a brace/statement bound.
  #     None of the pre-existing scanners handled `<<<` at all.
  #   * PHP-8 attribute aware — `#[Route(...)]` is code, not a `#` comment.
  #   * linear on multi-byte input — the source is materialised once into an
  #     `Array(Char)` with O(1) indexing, so CJK-commented controllers stay
  #     O(n) instead of the O(n^2) that `String#[](Int)` caused.
  #
  # The lexer masks every non-code region (strings, comments, heredoc/nowdoc
  # bodies) into spaces in `@masked` while preserving newlines and overall
  # length, so the structural helpers below are plain depth counters over
  # `@masked` with no string-state bookkeeping of their own.
  class PhpLexer
    # Code with strings/comments/heredoc bodies blanked to spaces. Same
    # character length as the source; newlines preserved so line/offset math
    # against the original content stays valid.
    getter masked : Array(Char)

    @chars : Array(Char)
    @size : Int32
    # Recorded non-code regions as {kind, start, end_exclusive}. Used for
    # `skip_ranges` and to splice string/comment tokens into `tokens`.
    @spans : Array(Tuple(Symbol, Int32, Int32))
    @tokens : Array(PhpToken)?
    @skip_ranges : Array(Range(Int32, Int32))?

    def initialize(source : String)
      @chars = source.chars
      @size = @chars.size
      @masked = Array(Char).new(@size)
      @spans = [] of Tuple(Symbol, Int32, Int32)
      @tokens = nil
      @skip_ranges = nil
      scan
    end

    private def ident_char?(c : Char) : Bool
      c == '_' || c.ascii_alphanumeric? || c.ord >= 0x80
    end

    private def ident_start?(c : Char) : Bool
      c == '_' || c.ascii_letter? || c.ord >= 0x80
    end

    # Single masking pass. Walks the character array once, copying code
    # characters into `@masked` verbatim and blanking the interior of strings,
    # comments and heredoc/nowdoc bodies (newlines kept). Each masked region is
    # recorded in `@spans`.
    private def scan
      i = 0
      while i < @size
        c = @chars[i]
        nxt = i + 1 < @size ? @chars[i + 1] : '\0'

        if c == '/' && nxt == '/'
          i = mask_line_comment(i)
        elsif c == '#' && nxt != '['
          # `#` is a line comment, but `#[` opens a PHP 8 attribute (code).
          i = mask_line_comment(i)
        elsif c == '/' && nxt == '*'
          i = mask_block_comment(i)
        elsif c == '<' && nxt == '<' && i + 2 < @size && @chars[i + 2] == '<'
          consumed = mask_heredoc(i)
          if consumed
            i = consumed
          else
            @masked << c
            i += 1
          end
        elsif c == '"' || c == '\''
          i = mask_string(i, c)
        else
          @masked << c
          i += 1
        end
      end
    end

    # Blank from `start` (a `/` or `#`) to end of line; the newline itself is
    # left intact. Returns the index just past the comment body.
    private def mask_line_comment(start : Int32) : Int32
      i = start
      while i < @size && @chars[i] != '\n'
        @masked << ' '
        i += 1
      end
      @spans << {:comment, start, i}
      i
    end

    private def mask_block_comment(start : Int32) : Int32
      # Blank the `/*` opener first and scan for `*/` from after it, so a
      # `/*/` is NOT mis-read as a self-closing comment (the opener's own `*`
      # must not double as the closer's `*`).
      @masked << ' '
      @masked << ' '
      i = start + 2
      while i < @size
        if @chars[i] == '*' && i + 1 < @size && @chars[i + 1] == '/'
          @masked << ' '
          @masked << ' '
          i += 2
          break
        end
        @masked << (@chars[i] == '\n' ? '\n' : ' ')
        i += 1
      end
      @spans << {:comment, start, i}
      i
    end

    # `start` points at the opening quote. Mask the literal (delimiters
    # included) up to and including the matching unescaped quote. A backslash
    # escapes the next character in both quote styles, matching the behaviour
    # of the scanners this replaces.
    private def mask_string(start : Int32, quote : Char) : Int32
      @masked << ' '
      i = start + 1
      escaped = false
      while i < @size
        c = @chars[i]
        @masked << (c == '\n' ? '\n' : ' ')
        if escaped
          escaped = false
        elsif c == '\\'
          escaped = true
        elsif c == quote
          i += 1
          break
        end
        i += 1
      end
      @spans << {:string, start, i}
      i
    end

    # `start` points at the first `<` of a `<<<` heredoc/nowdoc opener. Returns
    # the index just past the closing label, or nil when the construct is not a
    # real heredoc (so the caller can fall back to treating `<` as code).
    #
    # Opener:  `<<<` [ws] (LABEL | "LABEL" | 'LABEL') to end of line.
    # Closer:  a line whose first non-blank run is LABEL followed by a
    #          non-identifier character (PHP 7.3+ allows the label to be
    #          indented). Nowdoc uses a single-quoted label; both bodies are
    #          masked identically here since we never read inside them.
    private def mask_heredoc(start : Int32) : Int32?
      i = start + 3
      # optional spaces/tabs between <<< and the label
      while i < @size && (@chars[i] == ' ' || @chars[i] == '\t')
        i += 1
      end

      quote = '\0'
      if i < @size && (@chars[i] == '"' || @chars[i] == '\'')
        quote = @chars[i]
        i += 1
      end

      label_start = i
      # PHP labels start with a letter, `_` or a >=0x80 byte — never a digit;
      # a digit-leading run means this `<<<` isn't a heredoc opener.
      return unless i < @size && ident_start?(@chars[i])
      while i < @size && ident_char?(@chars[i])
        i += 1
      end
      label = @chars[label_start...i].join
      return if quote != '\0' && (i >= @size || @chars[i] != quote)
      i += 1 if quote != '\0'

      # The remainder of the opener line must be only blanks before the line
      # break: PHP forbids any code after the label on the opener line, so
      # anything else means this isn't a heredoc opener. A line break is
      # `\n`, `\r\n`, or a bare `\r` (classic-Mac endings).
      j = i
      while j < @size && @chars[j] != '\n' && @chars[j] != '\r'
        ch = @chars[j]
        return unless ch == ' ' || ch == '\t'
        j += 1
      end
      return if j >= @size # opener with no body/line break → not heredoc

      # Blank the opener from `start` up to (not including) the line break.
      (start...j).each { @masked << ' ' }
      i = j # at the line break

      # Walk body lines until a line that closes the label.
      while i < @size
        # i sits at a line break; copy it verbatim, treating `\r\n` as a unit.
        if @chars[i] == '\r' && i + 1 < @size && @chars[i + 1] == '\n'
          @masked << '\r'
          @masked << '\n'
          i += 2
        else
          @masked << @chars[i] # `\n` or a bare `\r`
          i += 1
        end
        line_start = i
        k = i
        while k < @size && (@chars[k] == ' ' || @chars[k] == '\t')
          k += 1
        end
        if matches_label?(k, label)
          # Blank the indentation + label, then continue normal scanning from
          # the char after the label (could be `;`, `,`, `)`, a line break...).
          (line_start...(k + label.size)).each { @masked << ' ' }
          @spans << {:heredoc, start, k + label.size}
          return k + label.size
        end

        # Not a closer: blank the whole line up to the next line break.
        while i < @size && @chars[i] != '\n' && @chars[i] != '\r'
          @masked << ' '
          i += 1
        end
      end

      # Unterminated heredoc: everything to EOF was masked.
      @spans << {:heredoc, start, @size}
      @size
    end

    private def matches_label?(pos : Int32, label : String) : Bool
      return false if pos + label.size > @size
      label.each_char_with_index do |lc, idx|
        return false if @chars[pos + idx] != lc
      end
      after = pos + label.size
      return true if after >= @size
      !ident_char?(@chars[after])
    end

    # ---- structural helpers (character indices) ----------------------------

    # Index of the delimiter that closes the `(`/`[`/`{` at `open_pos`, or nil.
    # Counts only the matching pair type, which is correct for balanced code
    # and mirrors the engine's `find_matching_php_close_brace`.
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
    # size when none is found. Mirrors `find_php_statement_end`.
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

    # Index of the first top-level expression terminator (`,` `;` or a closing
    # `) ] }` that would pop above the starting level) at or after `start_pos`.
    # Mirrors `find_arrow_expression_end`.
    def expression_end(start_pos : Int32) : Int32
      paren = 0
      bracket = 0
      brace = 0
      i = start_pos < 0 ? 0 : start_pos
      while i < @size
        case @masked[i]
        when '('
          paren += 1
        when ')'
          return i if paren == 0 && bracket == 0 && brace == 0
          paren -= 1 if paren > 0
        when '['
          bracket += 1
        when ']'
          return i if paren == 0 && bracket == 0 && brace == 0
          bracket -= 1 if bracket > 0
        when '{'
          brace += 1
        when '}'
          return i if paren == 0 && bracket == 0 && brace == 0
          brace -= 1 if brace > 0
        when ',', ';'
          return i if paren == 0 && bracket == 0 && brace == 0
        end
        i += 1
      end
      @size
    end

    # Character ranges occupied by strings, comments and heredoc/nowdoc bodies.
    def skip_ranges : Array(Range(Int32, Int32))
      @skip_ranges ||= @spans.map { |(_, s, e)| (s..e - 1) }
    end

    def in_code?(pos : Int32) : Bool
      return false unless 0 <= pos && pos < @size
      @spans.none? { |(_, s, e)| s <= pos && pos < e }
    end

    # ---- token stream ------------------------------------------------------

    # Lazily produce a flat token stream over the source: structural
    # delimiters, `->`/`::`/`=>` operators, identifiers, `$variables`, and one
    # token per string/comment/heredoc span. This is the reusable miniparser
    # surface for consumers that want to walk PHP structurally (e.g. following
    # a `Route::a(...)->b(...)->group(...)` method chain).
    def tokens : Array(PhpToken)
      @tokens ||= build_tokens
    end

    private def build_tokens : Array(PhpToken)
      result = [] of PhpToken
      span_idx = 0
      spans = @spans
      i = 0
      # Running line counter. Tokens are emitted at non-decreasing start
      # offsets, so advancing `line_cursor` monotonically keeps line lookup
      # O(n) total instead of the O(n^2) a rescan-from-zero per token caused.
      line = 1
      line_cursor = 0
      line_for = ->(pos : Int32) do
        while line_cursor < pos
          c = @chars[line_cursor]
          # `\n`, `\r\n` and a bare `\r` (classic-Mac, which the heredoc masking
          # also honours) each end a line; count the `\r` of `\r\n` only once.
          if c == '\n'
            line += 1
          elsif c == '\r' && (line_cursor + 1 >= @size || @chars[line_cursor + 1] != '\n')
            line += 1
          end
          line_cursor += 1
        end
        line
      end

      while i < @size
        # Emit any recorded span that starts here.
        if span_idx < spans.size && spans[span_idx][1] == i
          kind, s, e = spans[span_idx]
          result << PhpToken.new(kind, @chars[s...e].join, s, e, line_for.call(s))
          span_idx += 1
          i = e
          next
        end

        c = @masked[i]
        if c.ascii_whitespace?
          i += 1
        elsif c == '$' && i + 1 < @size && ident_start?(@masked[i + 1])
          start = i
          i += 1
          while i < @size && ident_char?(@masked[i])
            i += 1
          end
          result << PhpToken.new(:variable, @chars[start...i].join, start, i, line_for.call(start))
        elsif ident_start?(c)
          start = i
          while i < @size && ident_char?(@masked[i])
            i += 1
          end
          result << PhpToken.new(:ident, @chars[start...i].join, start, i, line_for.call(start))
        else
          kind, len = punct_at(i)
          if kind
            result << PhpToken.new(kind, @chars[i...i + len].join, i, i + len, line_for.call(i))
            i += len
          else
            i += 1
          end
        end
      end
      result
    end

    private def punct_at(i : Int32) : Tuple(Symbol?, Int32)
      c = @masked[i]
      n = i + 1 < @size ? @masked[i + 1] : '\0'
      case
      when c == '-' && n == '>' then {:arrow, 2}
      when c == ':' && n == ':' then {:double_colon, 2}
      when c == '=' && n == '>' then {:double_arrow, 2}
      when c == '('             then {:lparen, 1}
      when c == ')'             then {:rparen, 1}
      when c == '['             then {:lbracket, 1}
      when c == ']'             then {:rbracket, 1}
      when c == '{'             then {:lbrace, 1}
      when c == '}'             then {:rbrace, 1}
      when c == ';'             then {:semicolon, 1}
      when c == ','             then {:comma, 1}
      else                           {nil, 1}
      end
    end
  end
end
