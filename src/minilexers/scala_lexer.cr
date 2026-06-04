module Noir
  # A single token produced by `ScalaLexer#tokens`. `start`/`end` are
  # character indices into the original source (`end` exclusive); `line` is
  # the 1-based line of `start`.
  struct ScalaToken
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

  # ScalaLexer is a hand-rolled structural lexer for Scala source, modelled on
  # `Noir::PhpLexer` / `Noir::CSharpLexer`. The Scala analyzers used to strip
  # each line in isolation (`strip_non_code_with_state(line, 0, false)`),
  # resetting the block-comment depth and multiline-string flag on every line,
  # so route-shaped DSL inside a `"""…"""` triple-quoted string or a multi-line
  # `/* … */` comment leaked as phantom endpoints. This lexer threads that state
  # across the whole file once.
  #
  # Two masked views are produced, both the same length as the source with
  # newlines preserved:
  #   * `masked` (structural): strings, comments, triple-quotes and char
  #     literals are all blanked — used for brace/paren matching.
  #   * `code`: comments, triple-quoted bodies and char literals are blanked,
  #     but regular `"…"` string literals are PRESERVED, because Scala routes
  #     are string arguments (`path("users")`) that the analyzers read back.
  #
  # Scala specifics handled: nested block comments (`/* /* */ */`), triple-quoted
  # raw strings spanning lines, regular strings with `\` escapes, and `'x'` /
  # `'\n'` char literals (left as code when it is actually a `'sym` symbol).
  class ScalaLexer
    getter masked : Array(Char)
    getter code : Array(Char)

    @chars : Array(Char)
    @size : Int32
    @spans : Array(Tuple(Symbol, Int32, Int32))
    @tokens : Array(ScalaToken)?
    @skip_ranges : Array(Range(Int32, Int32))?
    @masked_lines : Array(String)?
    @code_lines : Array(String)?

    def initialize(source : String)
      @chars = source.chars
      @size = @chars.size
      @masked = Array(Char).new(@size)
      @code = Array(Char).new(@size)
      @spans = [] of Tuple(Symbol, Int32, Int32)
      @tokens = nil
      @skip_ranges = nil
      @masked_lines = nil
      @code_lines = nil
      scan
    end

    private def ident_char?(c : Char) : Bool
      c == '_' || c.ascii_alphanumeric? || c.ord >= 0x80
    end

    private def ident_start?(c : Char) : Bool
      c == '_' || c.ascii_letter? || c.ord >= 0x80
    end

    # Emit one source character to both views.
    private def emit(struct_c : Char, code_c : Char)
      @masked << struct_c
      @code << code_c
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
        elsif c == '"' && nxt == '"' && (i + 2 < @size ? @chars[i + 2] : '\0') == '"'
          i = mask_triple_string(i)
        elsif c == '"'
          i = mask_string(i)
        elsif c == '\'' && char_literal?(i)
          i = mask_char_literal(i)
        else
          emit(c, c)
          i += 1
        end
      end
    end

    private def mask_line_comment(start : Int32) : Int32
      i = start
      while i < @size && @chars[i] != '\n'
        emit(' ', ' ')
        i += 1
      end
      @spans << {:comment, start, i}
      i
    end

    # Scala block comments NEST: `/* /* */ */`. Track depth.
    private def mask_block_comment(start : Int32) : Int32
      depth = 0
      i = start
      while i < @size
        c = @chars[i]
        nxt = i + 1 < @size ? @chars[i + 1] : '\0'
        if c == '/' && nxt == '*'
          depth += 1
          emit(' ', ' ')
          emit(' ', ' ')
          i += 2
        elsif c == '*' && nxt == '/'
          depth -= 1
          emit(' ', ' ')
          emit(' ', ' ')
          i += 2
          break if depth == 0
        else
          emit((c == '\n' ? '\n' : ' '), (c == '\n' ? '\n' : ' '))
          i += 1
        end
      end
      @spans << {:comment, start, i}
      i
    end

    # `start` points at the first of `"""`. Triple-quoted strings are raw and
    # may span lines; close on the next `"""`. Blanked in BOTH views.
    private def mask_triple_string(start : Int32) : Int32
      emit(' ', ' ')
      emit(' ', ' ')
      emit(' ', ' ')
      i = start + 3
      while i < @size
        if @chars[i] == '"' && i + 2 < @size && @chars[i + 1] == '"' && @chars[i + 2] == '"'
          emit(' ', ' ')
          emit(' ', ' ')
          emit(' ', ' ')
          i += 3
          break
        end
        ch = @chars[i] == '\n' ? '\n' : ' '
        emit(ch, ch)
        i += 1
      end
      @spans << {:string, start, i}
      i
    end

    # Regular `"…"` string. Blanked in the structural view; PRESERVED (quotes
    # and content) in the code view so route literals stay readable.
    private def mask_string(start : Int32) : Int32
      emit(' ', '"')
      i = start + 1
      escaped = false
      while i < @size
        c = @chars[i]
        if c == '\n'
          emit('\n', '\n')
          i += 1
          break # unterminated single-line string
        end
        emit(' ', c)
        if escaped
          escaped = false
        elsif c == '\\'
          escaped = true
        elsif c == '"'
          i += 1
          break
        end
        i += 1
      end
      @spans << {:string, start, i}
      i
    end

    # True when the `'` at `pos` opens a real char literal (`'x'` or `'\x'`)
    # rather than a `'symbol` literal.
    private def char_literal?(pos : Int32) : Bool
      return false if pos + 2 >= @size
      if @chars[pos + 1] == '\\'
        # '\n' style: '  \  x  '
        pos + 3 < @size && @chars[pos + 3] == '\''
      else
        @chars[pos + 1] != '\'' && @chars[pos + 2] == '\''
      end
    end

    private def mask_char_literal(start : Int32) : Int32
      len = @chars[start + 1] == '\\' ? 4 : 3
      len.times { emit(' ', ' ') }
      @spans << {:string, start, start + len}
      start + len
    end

    # ---- structural helpers (character indices, over the structural view) ---

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

    # Structural masked source split into lines (1:1 with `String#lines`).
    def masked_lines : Array(String)
      @masked_lines ||= split_lines(@masked)
    end

    # Code masked source split into lines (1:1 with `String#lines`). Comments,
    # triple-quote bodies and char literals are blanked; regular strings kept.
    def code_lines : Array(String)
      @code_lines ||= split_lines(@code)
    end

    private def split_lines(buf : Array(Char)) : Array(String)
      out = [] of String
      line_start = 0
      i = 0
      while i < @size
        if @chars[i] == '\n'
          finish = i > line_start && @chars[i - 1] == '\r' ? i - 1 : i
          out << buf[line_start...finish].join
          line_start = i + 1
        end
        i += 1
      end
      out << buf[line_start...@size].join if line_start < @size
      out
    end

    # ---- token stream ------------------------------------------------------

    def tokens : Array(ScalaToken)
      @tokens ||= build_tokens
    end

    private def build_tokens : Array(ScalaToken)
      result = [] of ScalaToken
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
          result << ScalaToken.new(kind, @chars[s...e].join, s, e, line_for.call(s))
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
          result << ScalaToken.new(:ident, @chars[start...i].join, start, i, line_for.call(start))
        else
          kind, len = punct_at(i)
          if kind
            result << ScalaToken.new(kind, @chars[i...i + len].join, i, i + len, line_for.call(i))
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
      when c == '/'             then {:slash, 1}
      else                           {nil, 1}
      end
    end
  end
end
