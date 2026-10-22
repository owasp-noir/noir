require "./masked_lexer"

module Noir
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
    # Supplies `@masked`/`@size`/`@spans`/`@skip_ranges` plus the shared
    # `matching_delimiter`, `statement_end`, `skip_ranges`, `in_code?` and
    # identifier predicates.
    include MaskedLexer

    getter code : Array(Char)

    @chars : Array(Char)
    @masked_lines : Array(String)?
    @code_lines : Array(String)?

    def initialize(source : String)
      @chars = source.chars
      @size = @chars.size
      @masked = @chars.dup
      @code = @chars.dup
      @spans = [] of Tuple(Symbol, Int32, Int32)
      @skip_ranges = nil
      @masked_lines = nil
      @code_lines = nil
      scan
    end

    # Emit one source character to both views.
    private def emit(index : Int32, struct_c : Char, code_c : Char)
      @masked[index] = struct_c
      @code[index] = code_c
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
          i += 1
        end
      end
    end

    private def mask_line_comment(start : Int32) : Int32
      i = start
      while i < @size && @chars[i] != '\n'
        emit(i, ' ', ' ')
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
          emit(i, ' ', ' ')
          emit(i + 1, ' ', ' ')
          i += 2
        elsif c == '*' && nxt == '/'
          depth -= 1
          emit(i, ' ', ' ')
          emit(i + 1, ' ', ' ')
          i += 2
          break if depth == 0
        else
          emit(i, (c == '\n' ? '\n' : ' '), (c == '\n' ? '\n' : ' '))
          i += 1
        end
      end
      @spans << {:comment, start, i}
      i
    end

    # `start` points at the first of `"""`. Triple-quoted strings are raw and
    # may span lines; close on the next `"""`. Blanked in BOTH views.
    private def mask_triple_string(start : Int32) : Int32
      interpolated = interpolated_string?(start)
      emit(start, ' ', ' ')
      emit(start + 1, ' ', ' ')
      emit(start + 2, ' ', ' ')
      i = start + 3
      while i < @size
        if @chars[i] == '"' && i + 2 < @size && @chars[i + 1] == '"' && @chars[i + 2] == '"'
          emit(i, ' ', ' ')
          emit(i + 1, ' ', ' ')
          emit(i + 2, ' ', ' ')
          i += 3
          break
        end
        if interpolated && escaped_dollar?(i)
          emit(i, ' ', ' ')
          emit(i + 1, ' ', ' ')
          i += 2
        elsif interpolated && interpolation_hole?(i)
          i = skip_interpolation(i, false)
        else
          ch = @chars[i] == '\n' ? '\n' : ' '
          emit(i, ch, ch)
          i += 1
        end
      end
      @spans << {:string, start, i}
      i
    end

    # Regular `"…"` string. Blanked in the structural view; PRESERVED (quotes
    # and content) in the code view so route literals stay readable.
    private def mask_string(start : Int32) : Int32
      interpolated = interpolated_string?(start)
      emit(start, ' ', '"')
      i = start + 1
      escaped = false
      while i < @size
        c = @chars[i]
        if c == '\n'
          emit(i, '\n', '\n')
          i += 1
          break # unterminated single-line string
        end

        if interpolated && !escaped && escaped_dollar?(i)
          # `$$` is how an interpolated string writes a literal `$`; it does
          # not open a hole.
          emit(i, ' ', c)
          emit(i + 1, ' ', '$')
          i += 2
        elsif interpolated && !escaped && interpolation_hole?(i)
          i = skip_interpolation(i, true)
        else
          # The `$ident` short form needs nothing special — it carries no
          # delimiters, so it is plain string content either way.
          emit(i, ' ', c)
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
      end
      @spans << {:string, start, i}
      i
    end

    # `s"…"` / `f"…"` / `raw"…"` and any custom interpolator glue the opening
    # quote straight onto an identifier; a plain literal never does.
    private def interpolated_string?(start : Int32) : Bool
      return false if start == 0
      ident_char?(@chars[start - 1])
    end

    private def escaped_dollar?(i : Int32) : Bool
      @chars[i] == '$' && i + 1 < @size && @chars[i + 1] == '$'
    end

    private def interpolation_hole?(i : Int32) : Bool
      @chars[i] == '$' && i + 1 < @size && @chars[i + 1] == '{'
    end

    # `${…}` inside an interpolated string is a nested CODE region, not string
    # content. Without tracking it, the first `"` inside the hole closed the
    # literal, the rest of the expression was lexed as code, and the next `"`
    # re-opened a string — so `s"x ${cfg("k")} y"` produced two string spans
    # with a stray `k` token between them, and any parenthesis that landed on
    # the wrong side of that split skewed the structural depth permanently
    # (`foo(s"${f("(")}")` left an unmatched `(` in the masked view).
    #
    # `start` points at the `$`; the return value is the index just past the
    # matching `}`. Every character in between is emitted as string content,
    # so the hole contributes no delimiter of its own to the structural view
    # and brace matching sees exactly what it saw before this fix.
    private def skip_interpolation(start : Int32, keep_code : Bool) : Int32
      i = start
      depth = 0
      while i < @size
        c = @chars[i]
        if c == '"'
          # A literal inside the hole: consume it whole so its quotes and
          # braces cannot be mistaken for the hole's terminator.
          i = skip_nested_literal(i, keep_code)
        else
          depth += 1 if c == '{'
          depth -= 1 if c == '}'
          emit_content(i, keep_code)
          i += 1
          break if depth == 0 && c == '}'
        end
      end
      i
    end

    # A `"…"` / `"""…"""` literal nested inside an interpolation hole. Emitted
    # as content, like the hole around it.
    private def skip_nested_literal(start : Int32, keep_code : Bool) : Int32
      i = start
      if start + 2 < @size && @chars[start + 1] == '"' && @chars[start + 2] == '"'
        3.times do
          emit_content(i, keep_code)
          i += 1
        end
        while i < @size
          if @chars[i] == '"' && i + 2 < @size && @chars[i + 1] == '"' && @chars[i + 2] == '"'
            3.times do
              emit_content(i, keep_code)
              i += 1
            end
            return i
          end
          emit_content(i, keep_code)
          i += 1
        end
        return i
      end

      emit_content(i, keep_code)
      i += 1
      escaped = false
      while i < @size
        c = @chars[i]
        emit_content(i, keep_code)
        i += 1
        if escaped
          escaped = false
        elsif c == '\\'
          escaped = true
        elsif c == '"' || c == '\n'
          break
        end
      end
      i
    end

    # Emit one character as string content: blanked structurally, and either
    # preserved (regular string, whose code view keeps route literals) or
    # blanked (triple-quoted string, blanked in both views).
    private def emit_content(index : Int32, keep_code : Bool)
      c = @chars[index]
      blank = c == '\n' ? '\n' : ' '
      emit(index, blank, keep_code ? c : blank)
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
      len.times { |k| emit(start + k, ' ', ' ') }
      @spans << {:string, start, start + len}
      start + len
    end

    # ---- structural helpers (character indices, over the structural view) ---
    #
    # `matching_delimiter`, `statement_end`, `skip_ranges` and `in_code?` come
    # from `Noir::MaskedLexer`. Only the Scala-specific views live here.

    # Structural masked source split into lines (1:1 with `String#lines`).
    def masked_lines : Array(String)
      @masked_lines ||= @masked.join.lines
    end

    # Code masked source split into lines (1:1 with `String#lines`). Comments,
    # triple-quote bodies and char literals are blanked; regular strings kept.
    def code_lines : Array(String)
      @code_lines ||= @code.join.lines
    end
  end
end
