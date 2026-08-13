require "./masked_lexer"

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
  # the structural helpers in `Noir::MaskedLexer` are plain depth counters over
  # `@masked`. The source is materialised once into an `Array(Char)` for O(1)
  # indexing, keeping the scan O(n) on multi-byte (e.g. CJK-commented) source.
  class CSharpLexer
    # Supplies `@masked`/`@size`/`@spans`/`@skip_ranges` plus the shared
    # `matching_delimiter`, `statement_end`, `skip_ranges`, `in_code?` and
    # identifier predicates.
    include MaskedLexer

    @chars : Array(Char)
    @tokens : Array(CSharpToken)?
    @masked_lines : Array(String)?
    @code_lines : Array(String)?
    @code_source : String?

    def initialize(source : String)
      @chars = source.chars
      @size = @chars.size
      @masked = @chars.dup
      @spans = [] of Tuple(Symbol, Int32, Int32)
      @tokens = nil
      @skip_ranges = nil
      @masked_lines = nil
      @code_lines = nil
      @code_source = nil
      scan
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
        start + 1
      end
    end

    private def mask_line_comment(start : Int32) : Int32
      i = start
      while i < @size && @chars[i] != '\n'
        @masked[i] = ' '
        i += 1
      end
      @spans << {:comment, start, i}
      i
    end

    private def mask_block_comment(start : Int32) : Int32
      # Blank the `/*` opener first, then scan for `*/` from after it so `/*/`
      # is not mis-read as self-closing.
      @masked[start] = ' '
      @masked[start + 1] = ' '
      i = start + 2
      while i < @size
        if @chars[i] == '*' && i + 1 < @size && @chars[i + 1] == '/'
          @masked[i] = ' '
          @masked[i + 1] = ' '
          i += 2
          break
        end
        @masked[i] = ' ' unless @chars[i] == '\n'
        i += 1
      end
      @spans << {:comment, start, i}
      i
    end

    # `start` points at the opening `'`. Masks a char literal, honouring a
    # single backslash escape (`'\''`, `'\\'`, `'\}'`).
    private def mask_char_literal(start : Int32) : Int32
      @masked[start] = ' '
      i = start + 1
      escaped = false
      while i < @size
        c = @chars[i]
        @masked[i] = ' ' unless c == '\n'
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
      (start...quote_pos).each { |idx| @masked[idx] = ' ' }

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
          @masked[quote_pos] = ' '
          @masked[quote_pos + 1] = ' '
          @spans << {:string, start, quote_pos + 2}
          return quote_pos + 2
        end
      end

      @masked[quote_pos] = ' ' # opening quote
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

        @masked[i] = ' ' unless c == '\n'
        if escaped
          escaped = false
          i += 1
          next
        end

        if verbatim
          if c == '"'
            if i + 1 < @size && @chars[i + 1] == '"'
              @masked[i + 1] = ' ' # the doubled (escaped) quote
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
            @masked[i + 1] = ' '
            i += 2
            next
          end
          interp_depth += 1
        elsif interpolated && c == '}'
          if i + 1 < @size && @chars[i + 1] == '}'
            @masked[i + 1] = ' '
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
      fence.times { |k| @masked[quote_pos + k] = ' ' }
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
            fence.times { |k| @masked[i + k] = ' ' }
            i += fence
            @spans << {:string, start, i}
            return i
          end
          run.times { |k| @masked[i + k] = ' ' }
          i += run
        else
          @masked[i] = ' ' unless @chars[i] == '\n'
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
        run.times { |k| @masked[quote_pos + k] = ' ' }
        i = quote_pos + run
        while i < @size
          if @chars[i] == '"'
            r = 0
            while i + r < @size && @chars[i + r] == '"'
              r += 1
            end
            if r >= run
              run.times { |k| @masked[i + k] = ' ' }
              return i + run
            end
            r.times { |k| @masked[i + k] = ' ' }
            i += r
          else
            @masked[i] = ' ' unless @chars[i] == '\n'
            i += 1
          end
        end
        return @size
      end

      if run == 2 && !verbatim # empty "" string
        @masked[quote_pos] = ' '
        @masked[quote_pos + 1] = ' '
        return quote_pos + 2
      end

      @masked[quote_pos] = ' ' # opening quote
      i = quote_pos + 1
      escaped = false
      while i < @size
        c = @chars[i]
        @masked[i] = ' ' unless c == '\n'
        if verbatim
          if c == '"'
            if i + 1 < @size && @chars[i + 1] == '"'
              @masked[i + 1] = ' ' # doubled (escaped) quote
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
    #
    # `matching_delimiter`, `statement_end`, `skip_ranges` and `in_code?` come
    # from `Noir::MaskedLexer`. Only the C#-specific views live here.

    # The masked source split into lines, parallel to `source.lines`. Strings,
    # comments and char literals are blanked, so the C# analyzers can run their
    # existing per-line `line.count('{')` / `line.count('(')` counters over
    # `masked_lines[i]` (structure) while emitting `lines[i]` (real text).
    def masked_lines : Array(String)
      @masked_lines ||= begin
        masked_str = String.build(@size) do |io|
          @masked.each { |c| io << c }
        end
        masked_str.lines
      end
    end

    # The source with **comments only** blanked to spaces — string and char
    # literals are kept intact. Line count and every column index are
    # preserved, so a caller can keep reporting the original line number while
    # scanning text that a commented-out (or documentation-example) route can
    # no longer reach.
    #
    # `masked_lines` is the wrong tool for that job: it also blanks the string
    # literals a route extractor needs to read. ASP.NET Core's own source
    # carries `/// app.MapGet("/from-route/{id}", …)` inside `<example>` XML
    # docs, which a raw scan happily emits as an endpoint.
    def code_source : String
      @code_source ||= begin
        if @spans.none? { |(kind, _, _)| kind == :comment }
          # No comments at all — the common case for generated or terse
          # sources. Skip the char-array copy entirely.
          String.build(@size) { |io| @chars.each { |c| io << c } }
        else
          chars = @chars.dup
          @spans.each do |(kind, start, finish)|
            next unless kind == :comment
            (start...finish).each do |idx|
              next if idx >= @size
              chars[idx] = ' ' unless chars[idx] == '\n'
            end
          end
          String.build(@size) { |io| chars.each { |c| io << c } }
        end
      end
    end

    def code_lines : Array(String)
      @code_lines ||= code_source.lines
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
