module Noir
  # A single token produced by `CSharpLexer#tokens`. `start`/`end` are
  # character indices into the original source (`end` exclusive); `line` is
  # the 1-based line of `start`.
  struct CSharpToken
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

  # CSharpLexer is a hand-rolled structural lexer for C# source, modelled on
  # `Noir::PhpLexer`. The C# analyzers count `{`/`}`/`(`/`)` per line with no
  # string awareness (`line.count('{') - line.count('}')`), so a single `}` or
  # `(` inside a string literal truncates a method block (dropping callees) or
  # makes a signature run away (dropping parameters). This lexer masks every
  # non-code region in one linear pass so those counters can run over code only.
  #
  # Handles the C# string zoo:
  #   * regular     `"…"`           backslash escapes
  #   * verbatim    `@"…"`          `""` is an escaped quote, `\` is literal
  #   * interpolated `$"…{expr}…"`  `{{`/`}}` are literal braces; a `"` inside a
  #                                 `{ }` hole opens a nested string
  #   * combined    `$@"…"` / `@$"…"`
  #   * raw         `"""…"""`       (and `$"""…"""`) variable-length quote fence
  #   * char        `'x'` / `'\}'` / `'"'`
  #   * comments    `//…` and `/* … */`
  #
  # Every literal is masked to spaces (newlines preserved, length unchanged), so
  # the structural helpers below are plain depth counters over `@masked`. The
  # source is materialised once into an `Array(Char)` for O(1) indexing, keeping
  # the scan O(n) on multi-byte (e.g. CJK-commented) source.
  class CSharpLexer
    getter masked : Array(Char)

    @chars : Array(Char)
    @size : Int32
    @spans : Array(Tuple(Symbol, Int32, Int32))
    @tokens : Array(CSharpToken)?
    @skip_ranges : Array(Range(Int32, Int32))?
    @masked_lines : Array(String)?

    def initialize(source : String)
      @chars = source.chars
      @size = @chars.size
      @masked = Array(Char).new(@size)
      @spans = [] of Tuple(Symbol, Int32, Int32)
      @tokens = nil
      @skip_ranges = nil
      @masked_lines = nil
      scan
    end

    private def ident_char?(c : Char) : Bool
      c == '_' || c.ascii_alphanumeric? || c.ord >= 0x80
    end

    private def ident_start?(c : Char) : Bool
      c == '_' || c.ascii_letter? || c.ord >= 0x80
    end

    private def scan
      i = 0
      while i < @size
        c = @chars[i]
        nxt = i + 1 < @size ? @chars[i + 1] : '\0'

        if c == '/' && nxt == '/'
          i = mask_line_comment(i)
        elsif c == '/' && nxt == '*'
          i = mask_block_comment(i)
        elsif c == '\''
          i = mask_char_literal(i)
        elsif c == '"'
          i = mask_string(i, i, false, false)
        elsif c == '@' || c == '$'
          i = dispatch_prefixed_string(i)
        else
          @masked << c
          i += 1
        end
      end
    end

    # `@` and `$` may prefix a string (`@"`, `$"`, `$@"`, `@$"`) or be ordinary
    # code (`@class` verbatim identifier, a stray `$`). Only treat the run as a
    # string when a `"` follows it.
    private def dispatch_prefixed_string(start : Int32) : Int32
      j = start
      verbatim = false
      interpolated = false
      while j < @size && (@chars[j] == '@' || @chars[j] == '$')
        verbatim = true if @chars[j] == '@'
        interpolated = true if @chars[j] == '$'
        j += 1
      end
      if j < @size && @chars[j] == '"'
        mask_string(start, j, verbatim, interpolated)
      else
        @masked << @chars[start]
        start + 1
      end
    end

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
      # Blank the `/*` opener first, then scan for `*/` from after it so `/*/`
      # is not mis-read as self-closing.
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

    # `start` points at the opening `'`. Masks a char literal, honouring a
    # single backslash escape (`'\''`, `'\\'`, `'\}'`).
    private def mask_char_literal(start : Int32) : Int32
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
        elsif c == '\''
          i += 1
          break
        end
        i += 1
      end
      @spans << {:string, start, i}
      i
    end

    # `start` is the first prefix char (or the quote when unprefixed);
    # `quote_pos` is the opening `"`. Dispatches to raw / verbatim / regular
    # masking and records one `:string` span spanning the whole literal.
    private def mask_string(start : Int32, quote_pos : Int32, verbatim : Bool, interpolated : Bool) : Int32
      (start...quote_pos).each { @masked << ' ' }

      unless verbatim
        run = 0
        j = quote_pos
        while j < @size && @chars[j] == '"'
          run += 1
          j += 1
        end
        if run >= 3
          return mask_raw_string(start, quote_pos, run)
        end
        if run == 2
          @masked << ' '
          @masked << ' '
          @spans << {:string, start, quote_pos + 2}
          return quote_pos + 2
        end
      end

      @masked << ' ' # opening quote
      i = quote_pos + 1
      interp_depth = 0
      escaped = false
      while i < @size
        c = @chars[i]

        # A string opening inside a `{ … }` interpolation hole is a nested
        # string, NOT the end of the outer literal. Skip the whole nested
        # literal — regular, verbatim `@"`, raw `"""`, or `$`-prefixed — so its
        # quotes and braces can't change interp_depth or terminate early.
        if interpolated && interp_depth > 0 && c == '"' && !escaped
          i = mask_nested_hole_string(i)
          next
        end

        @masked << (c == '\n' ? '\n' : ' ')
        if escaped
          escaped = false
          i += 1
          next
        end

        if verbatim
          if c == '"'
            if i + 1 < @size && @chars[i + 1] == '"'
              @masked << ' ' # the doubled (escaped) quote
              i += 2
              next
            end
            i += 1
            break
          end
        else
          if c == '\\'
            escaped = true
            i += 1
            next
          end
        end

        if interpolated && c == '{'
          if i + 1 < @size && @chars[i + 1] == '{'
            @masked << ' '
            i += 2
            next
          end
          interp_depth += 1
        elsif interpolated && c == '}'
          if i + 1 < @size && @chars[i + 1] == '}'
            @masked << ' '
            i += 2
            next
          end
          interp_depth -= 1 if interp_depth > 0
        elsif c == '"'
          # interp_depth == 0 here — the hole case is handled above.
          i += 1
          break
        end

        i += 1
      end

      @spans << {:string, start, i}
      i
    end

    # Mask a C# 11 raw string literal: opened by `fence` quotes (>= 3), closed
    # by the first run of `fence` quotes. Content (including `"`, `{`, `}`) is
    # literal and fully masked.
    private def mask_raw_string(start : Int32, quote_pos : Int32, fence : Int32) : Int32
      fence.times { @masked << ' ' }
      i = quote_pos + fence
      while i < @size
        if @chars[i] == '"'
          run = 0
          j = i
          while j < @size && @chars[j] == '"'
            run += 1
            j += 1
          end
          if run >= fence
            fence.times { @masked << ' ' }
            i += fence
            @spans << {:string, start, i}
            return i
          end
          run.times { @masked << ' ' }
          i += run
        else
          @masked << (@chars[i] == '\n' ? '\n' : ' ')
          i += 1
        end
      end
      @spans << {:string, start, @size}
      @size
    end

    # `quote_pos` is the opening `"` of a string nested inside an interpolation
    # hole. Mask the whole nested literal (recognising a `@` verbatim prefix via
    # lookbehind and a `"""` raw fence) and return the index just past it.
    private def mask_nested_hole_string(quote_pos : Int32) : Int32
      verbatim = quote_pos > 0 && @chars[quote_pos - 1] == '@'

      run = 0
      j = quote_pos
      while j < @size && @chars[j] == '"'
        run += 1
        j += 1
      end

      if run >= 3 # raw nested string: close on the next run of `run` quotes
        run.times { @masked << ' ' }
        i = quote_pos + run
        while i < @size
          if @chars[i] == '"'
            r = 0
            while i + r < @size && @chars[i + r] == '"'
              r += 1
            end
            if r >= run
              run.times { @masked << ' ' }
              return i + run
            end
            r.times { @masked << ' ' }
            i += r
          else
            @masked << (@chars[i] == '\n' ? '\n' : ' ')
            i += 1
          end
        end
        return @size
      end

      if run == 2 && !verbatim # empty "" string
        @masked << ' '
        @masked << ' '
        return quote_pos + 2
      end

      @masked << ' ' # opening quote
      i = quote_pos + 1
      escaped = false
      while i < @size
        c = @chars[i]
        @masked << (c == '\n' ? '\n' : ' ')
        if verbatim
          if c == '"'
            if i + 1 < @size && @chars[i + 1] == '"'
              @masked << ' ' # doubled (escaped) quote
              i += 2
              next
            end
            return i + 1
          end
        elsif escaped
          escaped = false
        elsif c == '\\'
          escaped = true
        elsif c == '"'
          return i + 1
        end
        i += 1
      end
      i
    end

    # ---- structural helpers (character indices) ----------------------------

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
    # size when none is found.
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

    def skip_ranges : Array(Range(Int32, Int32))
      @skip_ranges ||= @spans.map { |(_, s, e)| (s..e - 1) }
    end

    def in_code?(pos : Int32) : Bool
      return false unless 0 <= pos && pos < @size
      @spans.none? { |(_, s, e)| s <= pos && pos < e }
    end

    # The masked source split into lines, parallel to `source.lines`. Strings,
    # comments and char literals are blanked, so the C# analyzers can run their
    # existing per-line `line.count('{')` / `line.count('(')` counters over
    # `masked_lines[i]` (structure) while emitting `lines[i]` (real text).
    def masked_lines : Array(String)
      @masked_lines ||= begin
        # Mirror `String#lines` (chomp: drop the trailing empty segment when the
        # source ends in `\n`) so masked_lines[i] aligns 1:1 with content.lines[i].
        out = [] of String
        line_start = 0
        i = 0
        while i < @size
          if @chars[i] == '\n'
            # Chomp the `\r` of a `\r\n` so each line matches `String#lines`.
            finish = i > line_start && @chars[i - 1] == '\r' ? i - 1 : i
            out << @masked[line_start...finish].join
            line_start = i + 1
          end
          i += 1
        end
        out << @masked[line_start...@size].join if line_start < @size
        out
      end
    end

    # ---- token stream ------------------------------------------------------

    def tokens : Array(CSharpToken)
      @tokens ||= build_tokens
    end

    private def build_tokens : Array(CSharpToken)
      result = [] of CSharpToken
      span_idx = 0
      spans = @spans
      i = 0
      line = 1
      line_cursor = 0
      line_for = ->(pos : Int32) do
        while line_cursor < pos
          line += 1 if @chars[line_cursor] == '\n'
          line_cursor += 1
        end
        line
      end

      while i < @size
        if span_idx < spans.size && spans[span_idx][1] == i
          kind, s, e = spans[span_idx]
          result << CSharpToken.new(kind, @chars[s...e].join, s, e, line_for.call(s))
          span_idx += 1
          i = e
          next
        end

        c = @masked[i]
        if c.ascii_whitespace?
          i += 1
        elsif ident_start?(c)
          start = i
          while i < @size && ident_char?(@masked[i])
            i += 1
          end
          result << CSharpToken.new(:ident, @chars[start...i].join, start, i, line_for.call(start))
        else
          kind, len = punct_at(i)
          if kind
            result << CSharpToken.new(kind, @chars[i...i + len].join, i, i + len, line_for.call(i))
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
      when c == '=' && n == '>' then {:arrow, 2}
      when c == '('             then {:lparen, 1}
      when c == ')'             then {:rparen, 1}
      when c == '['             then {:lbracket, 1}
      when c == ']'             then {:rbracket, 1}
      when c == '{'             then {:lbrace, 1}
      when c == '}'             then {:rbrace, 1}
      when c == ';'             then {:semicolon, 1}
      when c == ','             then {:comma, 1}
      when c == '.'             then {:dot, 1}
      else                           {nil, 1}
      end
    end
  end
end
