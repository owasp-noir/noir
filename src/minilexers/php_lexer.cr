require "./masked_lexer"

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
  #   * open/close-tag aware — a `.php` file is HTML with islands of code in
  #     it, so everything outside `<?php … ?>` is inert output text. Lexing it
  #     as code let a lone apostrophe in `<h1>Today's report</h1>` open a
  #     string that masked the rest of the file, silently dropping every route
  #     declared below it.
  #   * heredoc/nowdoc aware — `<<<EOT … EOT` / `<<<'EOT' … EOT` bodies are
  #     masked, so route-shaped text or stray `{};` inside a heredoc can no
  #     longer leak as a false endpoint or corrupt a brace/statement bound.
  #     None of the pre-existing scanners handled `<<<` at all.
  #   * PHP-8 attribute aware — `#[Route(...)]` is code, not a `#` comment.
  #   * linear on multi-byte input — the source is materialised once into an
  #     `Array(Char)` with O(1) indexing, so CJK-commented controllers stay
  #     O(n) instead of the O(n^2) that `String#[](Int)` caused.
  #
  # The lexer masks every non-code region (inline HTML, strings, comments,
  # heredoc/nowdoc bodies) into spaces in `@masked` while preserving newlines and overall
  # length, so the structural helpers in `Noir::MaskedLexer` are plain depth
  # counters over `@masked` with no string-state bookkeeping of their own.
  class PhpLexer
    # Supplies `@masked`/`@size`/`@spans`/`@skip_ranges` plus the shared
    # `matching_delimiter`, `statement_end`, `skip_ranges`, `in_code?` and
    # identifier predicates.
    include MaskedLexer

    @chars : Array(Char)
    @tokens : Array(PhpToken)?

    # `source` is a whole `.php` file by default, so lexing starts in HTML
    # mode: nothing is code until the first `<?php` / `<?=`. Pass
    # `php_mode: true` when `source` is a fragment already carved out of a PHP
    # region (a closure body handed back for a recursive pass, say), which by
    # construction has no opening tag of its own.
    def initialize(source : String, *, php_mode : Bool = false)
      @chars = source.chars
      @size = @chars.size
      @masked = Array(Char).new(@size)
      @spans = [] of Tuple(Symbol, Int32, Int32)
      @tokens = nil
      @skip_ranges = nil
      scan(php_mode)
    end

    # Single masking pass. Walks the character array once, copying code
    # characters into `@masked` verbatim and blanking the interior of strings,
    # comments, heredoc/nowdoc bodies and inline-HTML regions (newlines kept).
    # Each masked region is recorded in `@spans`.
    private def scan(php_mode : Bool)
      i = php_mode ? 0 : mask_inline_html(0)
      while i < @size
        c = @chars[i]
        nxt = i + 1 < @size ? @chars[i + 1] : '\0'

        # `?>` leaves PHP mode. This test sits alongside the string/comment/
        # heredoc branches rather than ahead of them on purpose: those branches
        # consume their whole region, so a `?>` written inside a literal or a
        # block comment never reaches the top of this loop and cannot close
        # the block.
        if c == '?' && nxt == '>'
          i = mask_inline_html(i)
        elsif c == '/' && nxt == '/'
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

    # `start` is the first character of an inert region: the top of a file that
    # has not opened PHP yet, or the `?` of the `?>` that just closed it.
    # Everything from there up to and including the next open tag is literal
    # output, not code — masking it is what stops an apostrophe in prose, a
    # `#`, a `//` or a `<<<` in markup from opening a string, a comment or a
    # heredoc that runs to EOF and swallows the code below.
    #
    # The region is blanked into `@masked` with its line breaks kept (every
    # analyzer reports `code_path` lines from these offsets, so the character
    # count and the newline positions have to survive) and recorded as a single
    # `:html` span. Returns the index just past the open tag, or `@size` when
    # the file never opens PHP again — a file whose last PHP block runs to EOF
    # without a closing `?>` is the recommended style, not an error.
    private def mask_inline_html(start : Int32) : Int32
      i = start
      while i < @size
        if len = open_tag_len(i)
          len.times { @masked << ' ' }
          i += len
          @spans << {:html, start, i}
          return i
        end
        c = @chars[i]
        @masked << (c == '\n' || c == '\r' ? c : ' ')
        i += 1
      end
      @spans << {:html, start, @size} if start < @size
      @size
    end

    # Length of the PHP open tag at `i`, or nil when `i` isn't one. `<?=` is
    # the short echo tag and opens code just like `<?php`, which is spelled
    # case-insensitively and must be followed by whitespace or EOF (`<?phpinfo`
    # is text). The bare `<?` short tag is accepted too — legacy files that use
    # it would otherwise be read as one giant HTML blob and lose every route —
    # except before `xml`, which would make an XML processing instruction open
    # a PHP block in a template.
    private def open_tag_len(i : Int32) : Int32?
      return unless @chars[i] == '<' && i + 1 < @size && @chars[i + 1] == '?'
      return 3 if @chars[i + 2]? == '='
      if @chars[i + 2]?.try(&.downcase) == 'p' &&
         @chars[i + 3]?.try(&.downcase) == 'h' &&
         @chars[i + 4]?.try(&.downcase) == 'p'
        after = @chars[i + 5]?
        return 5 if after.nil? || after.ascii_whitespace?
      end
      return if @chars[i + 2]?.try(&.downcase) == 'x' &&
                @chars[i + 3]?.try(&.downcase) == 'm' &&
                @chars[i + 4]?.try(&.downcase) == 'l'
      2
    end

    # Blank from `start` (a `/` or `#`) to end of line; the newline itself is
    # left intact. Returns the index just past the comment body.
    private def mask_line_comment(start : Int32) : Int32
      i = start
      while i < @size && @chars[i] != '\n'
        # A `//` or `#` comment also ends at `?>`: PHP leaves the tag outside
        # the comment so that it still closes the block. Without this a
        # one-line `<?php // note ?>` would keep the lexer in PHP mode over all
        # the markup that follows.
        break if @chars[i] == '?' && @chars[i + 1]? == '>'
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
    #
    # `matching_delimiter`, `statement_end`, `skip_ranges` and `in_code?` come
    # from `Noir::MaskedLexer`. Only the PHP-specific one lives here.

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
          span_idx += 1
          i = e
          # Inert markup outside `<?php … ?>` is masked like a string literal
          # so it can never be read as code, but unlike a literal it is not
          # part of the program: a `.php` file with no open tag at all is pure
          # HTML and has no tokens.
          next if kind == :html
          result << PhpToken.new(kind, @chars[s...e].join, s, e, line_for.call(s))
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
