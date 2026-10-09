module Noir
  # JSLiteralScanner provides utilities for scanning JavaScript source code
  # while properly skipping string literals, comments, template literals, and regex.
  # This ensures parenthesis/brace matching doesn't get confused by literals.
  #
  # Implementation note: every public entry point takes CHAR indices and
  # returns CHAR indices (callers slice with char-based `String#[]`). The
  # scanners themselves run over an indexed char source instead of probing
  # the string with `String#[](Int)` — which is O(index) once a string
  # contains any multi-byte UTF-8 — and accumulate through `String::Builder`
  # instead of per-char `String#+`, which reallocated the whole prefix on
  # every append. ASCII content (the overwhelmingly common case) scans its
  # byte slice with zero allocation; non-ASCII content pays one up-front
  # `chars` materialization and stays linear.
  module JSLiteralScanner
    # Result of scanning with literal awareness
    struct ScanResult
      getter content : String
      getter end_pos : Int32

      def initialize(@content : String, @end_pos : Int32)
      end
    end

    # Keywords that can precede a regex literal in JavaScript
    REGEX_PRECEDING_KEYWORDS = ["return", "case", "throw", "in", "of", "typeof", "instanceof", "void", "delete", "new"]

    # Characters that can precede a regex literal (operators/punctuation expecting expression).
    # '<' is deliberately absent: `a < /re/` is never written, while JSX
    # closing tags (`</div>`) put a '/' after '<' on every other line.
    REGEX_PRECEDING_CHARS = Set{'(', '[', '{', ',', ':', ';', '=', '!', '&', '|', '?', '+', '-', '*', '%', '>', '~', '^'}

    # The regex-context checks only ever look at the tail of the scanned
    # output: the last non-whitespace char, and `ends_with?` against the
    # keywords above (longest: "instanceof", 10 chars). A rolling window of
    # this size replaces re-materializing the whole accumulated prefix on
    # every '/' encountered.
    KEYWORD_WINDOW = 12

    # Extract content between parentheses while skipping literals
    # Returns the content inside the parentheses (not including the parens)
    def self.extract_paren_content(content : String, start_pos : Int32) : ScanResult?
      return unless start_pos < content.size

      if single_byte?(content)
        extract_paren_content_impl(content.to_slice, start_pos)
      else
        extract_paren_content_impl(content.chars, start_pos)
      end
    end

    # Find matching closing brace, skipping literals
    def self.find_matching_brace(content : String, open_brace_idx : Int32) : Int32?
      if single_byte?(content)
        find_matching_impl(content.to_slice, open_brace_idx, '{', '}')
      else
        find_matching_impl(content.chars, open_brace_idx, '{', '}')
      end
    end

    # Find matching closing paren, skipping literals
    def self.find_matching_paren(content : String, open_paren_idx : Int32) : Int32?
      if single_byte?(content)
        find_matching_impl(content.to_slice, open_paren_idx, '(', ')')
      else
        find_matching_impl(content.chars, open_paren_idx, '(', ')')
      end
    end

    # BYTE-offset variants over the raw UTF-8 bytes, for any content. Every
    # delimiter, quote and comment marker is ASCII and no byte of a
    # multi-byte char is, so non-ASCII text is just opaque bytes here — and
    # the walk costs only the distance scanned, where the char variants above
    # materialize `content.chars` on every call once a file is non-ASCII.
    def self.find_matching_brace_at_byte(content : String, open_brace_byte : Int32) : Int32?
      find_matching_impl(content.to_slice, open_brace_byte, '{', '}')
    end

    def self.find_matching_paren_at_byte(content : String, open_paren_byte : Int32) : Int32?
      find_matching_impl(content.to_slice, open_paren_byte, '(', ')')
    end

    # --- indexed char access (ASCII byte slice / char array) ---

    # O(1) ASCII probe: a UTF-8 string is all-ASCII iff its char count
    # equals its byte count, and `String#size` is computed once per string
    # then cached. (`String#ascii_only?` instead re-scans every byte on
    # each call, which would put an O(n) toll on every dispatch — measured
    # as an 86× slowdown on repeated brace matching over the same file.)
    private def self.single_byte?(content : String) : Bool
      content.bytesize == content.size
    end

    private def self.chr(src : Bytes, i : Int32) : Char
      # A byte of a multi-byte char maps to U+0080..U+00FF, which never
      # equals the ASCII syntax the scanner compares against.
      src[i].unsafe_chr
    end

    private def self.chr(src : Array(Char), i : Int32) : Char
      src[i]
    end

    private def self.word_string(src : Bytes, from : Int32, to : Int32) : String
      String.new(src[from, to - from])
    end

    private def self.word_string(src : Array(Char), from : Int32, to : Int32) : String
      src[from...to].join
    end

    # --- core scanners ---

    private def self.extract_paren_content_impl(src, start_pos : Int32) : ScanResult
      size = src.size
      paren_depth = 1
      pos = start_pos
      window = Array(Char).new(KEYWORD_WINDOW)
      pending_ws = Array(Char).new(KEYWORD_WINDOW)
      regex_floor = 0

      result = String.build do |io|
        while pos < size && paren_depth > 0
          # Try to skip literals
          if skip_pos = scan_literal(src, size, pos, io, window, pending_ws)
            pos = skip_pos
            next
          end

          char = chr(src, pos)

          # Regex literals. A failed scan raises the floor to its line end,
          # so the line's other '/'s are division instead of each re-scanning
          # to the end of the line (quadratic on one long line).
          if char == '/' && pos >= regex_floor && looks_like_regex?(window)
            stop, closed = regex_literal_end(src, size, pos)
            if closed
              while pos < stop
                emit(io, window, pending_ws, chr(src, pos))
                pos += 1
              end
              next
            end
            regex_floor = stop
          end

          # Track parentheses depth
          if char == '('
            paren_depth += 1
          elsif char == ')'
            paren_depth -= 1
            break if paren_depth == 0
          end

          emit(io, window, pending_ws, char)
          pos += 1
        end
      end

      ScanResult.new(result, pos)
    end

    # Skips (and where applicable, appends) one comment/string/template
    # literal starting at `pos` (regex literals are the caller's). Returns the resume position, or nil
    # when `pos` does not start a literal. Comments are consumed without
    # appending; string/template/regex text is appended through `emit` so
    # the regex-context window stays in sync with the emitted output.
    private def self.scan_literal(src, size : Int32, pos : Int32, io : String::Builder,
                                  window : Array(Char), pending_ws : Array(Char)) : Int32?
      char = chr(src, pos)

      # Skip single-line comments
      if char == '/' && pos + 1 < size && chr(src, pos + 1) == '/'
        while pos < size && chr(src, pos) != '\n'
          pos += 1
        end
        return pos
      end

      # Skip multi-line comments
      if char == '/' && pos + 1 < size && chr(src, pos + 1) == '*'
        pos += 2
        while pos + 1 < size && !(chr(src, pos) == '*' && chr(src, pos + 1) == '/')
          pos += 1
        end
        pos += 2 if pos + 1 < size
        return pos
      end

      # Skip string literals (single/double quotes)
      if char == '"' || char == '\''
        quote = char
        emit(io, window, pending_ws, char)
        pos += 1
        while pos < size && chr(src, pos) != quote
          if chr(src, pos) == '\\' && pos + 1 < size
            emit(io, window, pending_ws, chr(src, pos))
            pos += 1
          end
          emit(io, window, pending_ws, chr(src, pos)) if pos < size
          pos += 1
        end
        emit(io, window, pending_ws, quote) if pos < size && chr(src, pos) == quote
        pos += 1
        return pos
      end

      # Skip template literals
      if char == '`'
        stop = template_literal_end(src, size, pos)
        while pos < stop
          emit(io, window, pending_ws, chr(src, pos))
          pos += 1
        end
        return pos
      end

      nil
    end

    # End (exclusive) of the template literal whose opening backtick is at
    # `pos`, or `size` when it never closes. `${ … }` substitutions are
    # tracked with their own brace depth, so a nested template
    # (`${items.map(i => `<li>${i}</li>`)}`), a string or a `}` inside a
    # substitution does not end the outer literal early. Each stack entry
    # is either TEMPLATE_TEXT or the brace depth of an open substitution;
    # an explicit stack keeps hostile nesting off the call stack.
    TEMPLATE_TEXT = -1

    def self.template_literal_end(src, size : Int32, pos : Int32) : Int32
      stack = [TEMPLATE_TEXT]
      regex_floor = 0
      pos += 1
      while pos < size
        c = chr(src, pos)
        if stack.last == TEMPLATE_TEXT
          if c == '\\'
            pos += 2
            next
          elsif c == '`'
            stack.pop
            return pos + 1 if stack.empty?
          elsif c == '$' && pos + 1 < size && chr(src, pos + 1) == '{'
            stack << 0
            pos += 1
          end
        else
          case c
          when '`'
            stack << TEMPLATE_TEXT
          when '\'', '"'
            pos += 1
            while pos < size && chr(src, pos) != c && chr(src, pos) != '\n'
              pos += chr(src, pos) == '\\' ? 2 : 1
            end
          when '/'
            if pos + 1 < size && chr(src, pos + 1) == '/'
              while pos < size && chr(src, pos) != '\n'
                pos += 1
              end
            elsif pos + 1 < size && chr(src, pos + 1) == '*'
              pos += 2
              while pos + 1 < size && !(chr(src, pos) == '*' && chr(src, pos + 1) == '/')
                pos += 1
              end
              pos += 1
            elsif pos >= regex_floor && regex_start?(src, pos)
              # `${ s.replace(/'/g, "") }` — the quote or brace in the
              # regex body must not open a string or shift the depth.
              stop, closed = regex_literal_end(src, size, pos)
              if closed
                pos = stop
                next
              end
              regex_floor = stop
            end
          when '{'
            stack[-1] += 1
          when '}'
            if stack.last == 0
              stack.pop
            else
              stack[-1] -= 1
            end
          end
        end
        pos += 1
      end
      size
    end

    # Scans the regex literal whose opening '/' is at `pos`. Returns
    # `{end, true}` (end exclusive, flags included) when it closes, or
    # `{line_end, false}` when no closing '/' appears before the newline (or
    # EOF) at `line_end`. A regex literal cannot span lines, so a '/' the
    # context rule misjudged (a JSX `</tag>`, `a++ / 2`) is division, not a
    # regex that swallows the rest of the file. Callers treat every '/'
    # before `line_end` as division afterwards.
    def self.regex_literal_end(src, size : Int32, pos : Int32) : Tuple(Int32, Bool)
      pos += 1
      in_char_class = false
      while pos < size
        c = chr(src, pos)
        return {pos, false} if c == '\n'
        if c == '\\'
          pos += 2
          next
        elsif c == '[' && !in_char_class
          in_char_class = true
        elsif c == ']' && in_char_class
          in_char_class = false
        elsif c == '/' && !in_char_class
          pos += 1
          while pos < size && chr(src, pos).in?('g', 'i', 'm', 's', 'u', 'y', 'd')
            pos += 1
          end
          return {pos, true}
        end
        pos += 1
      end
      {size, false}
    end

    # Appends `char` to the output and keeps the regex-context window
    # aligned with the rstrip'd output tail: trailing whitespace is held in
    # `pending_ws` and only flushed into the window once a non-whitespace
    # char follows (matching what `accumulated.rstrip` used to observe).
    private def self.emit(io : String::Builder, window : Array(Char), pending_ws : Array(Char), char : Char)
      io << char
      if char.whitespace?
        pending_ws.shift if pending_ws.size >= KEYWORD_WINDOW
        pending_ws << char
      else
        unless pending_ws.empty?
          pending_ws.each { |ws| window << ws }
          pending_ws.clear
        end
        window << char
        while window.size > KEYWORD_WINDOW
          window.shift
        end
      end
    end

    # The single rule for "can a '/' here start a regex literal?".
    #
    # `last_char` is the last non-whitespace character of the code scanned
    # so far (nil when nothing has been scanned yet) and `last_word` is the
    # identifier that ends at `last_char`, or "" when `last_char` is
    # punctuation. Every JavaScript scanner in the tree asks this question —
    # the literal scanners below, `JSRouteExtractor.strip_js_comments` and
    # `JSLexer#looks_like_regex?` — and they must agree: a '/' misread as
    # division lets the regex body's quotes and `//` open a string or a
    # comment that runs to EOF, which silently drops every route in the file.
    #
    # `before_last` is the raw character just before `last_char`: a '/'
    # after `i++` / `i--` is division, not a regex.
    def self.regex_context?(last_char : Char?, last_word : String, before_last : Char? = nil) : Bool
      return false unless last_char
      return false if (last_char == '+' || last_char == '-') && before_last == last_char
      return true if REGEX_PRECEDING_CHARS.includes?(last_char)
      return false if last_word.empty?
      REGEX_PRECEDING_KEYWORDS.includes?(last_word)
    end

    # Determine if '/' at current position likely starts a regex literal.
    # `window` is the rstrip'd tail of the scanned output — enough for both
    # the last-char probe and the trailing-word keyword probe.
    private def self.looks_like_regex?(window : Array(Char)) : Bool
      last_char = window.last?
      return false unless last_char
      return false unless REGEX_PRECEDING_CHARS.includes?(last_char) || word_char?(last_char)

      word = word_char?(last_char) ? window_tail_word(window) : ""
      regex_context?(last_char, word, window.size > 1 ? window[-2] : nil)
    end

    private def self.word_char?(char : Char) : Bool
      char.alphanumeric? || char == '_' || char == '$'
    end

    # The identifier ending at the window's last character. The window holds
    # 12 chars and the longest keyword ("instanceof") is 10, so any word that
    # fills the window is already longer than every keyword.
    private def self.window_tail_word(window : Array(Char)) : String
      start = window.size
      while start > 0 && word_char?(window[start - 1])
        start -= 1
      end
      window[start..].join
    end

    private def self.find_matching_impl(src, open_idx : Int32, open_char : Char, close_char : Char) : Int32?
      size = src.size
      count = 1
      idx = open_idx + 1
      regex_floor = 0

      while idx < size && count > 0
        # Try to skip literals
        if skip_idx = simple_literal_end(src, size, idx)
          idx = skip_idx
          next
        end

        # Regex literals, with the same failed-line floor as
        # `extract_paren_content_impl`.
        if chr(src, idx) == '/' && idx >= regex_floor && regex_start?(src, idx)
          stop, closed = regex_literal_end(src, size, idx)
          if closed
            idx = stop
            next
          end
          regex_floor = stop
        end

        case chr(src, idx)
        when open_char
          count += 1
        when close_char
          count -= 1
        end
        idx += 1

        return idx - 1 if count == 0
      end

      nil
    end

    # Simplified literal skip that doesn't accumulate content - just returns
    # new position (regex literals are the caller's).
    private def self.simple_literal_end(src, size : Int32, pos : Int32) : Int32?
      char = chr(src, pos)

      # Skip single-line comments
      if char == '/' && pos + 1 < size && chr(src, pos + 1) == '/'
        while pos < size && chr(src, pos) != '\n'
          pos += 1
        end
        return pos
      end

      # Skip multi-line comments
      if char == '/' && pos + 1 < size && chr(src, pos + 1) == '*'
        pos += 2
        while pos + 1 < size && !(chr(src, pos) == '*' && chr(src, pos + 1) == '/')
          pos += 1
        end
        pos += 2 if pos + 1 < size
        return pos
      end

      # Skip string literals
      if char == '"' || char == '\''
        quote = char
        pos += 1
        while pos < size && chr(src, pos) != quote
          if chr(src, pos) == '\\' && pos + 1 < size
            pos += 2
          else
            pos += 1
          end
        end
        pos += 1
        return pos
      end

      # Skip template literals
      return template_literal_end(src, size, pos) if char == '`'

      nil
    end

    # Does the '/' at `pos` start a regex literal, judged by looking back
    # at the code before it?
    private def self.regex_start?(src, pos : Int32) : Bool
      # Look back for regex-preceding context
      prev_idx = pos - 1
      while prev_idx > 0 && chr(src, prev_idx).whitespace?
        prev_idx -= 1
      end
      prev_char = prev_idx >= 0 ? chr(src, prev_idx) : '('

      # Extract the identifier ending at prev_char so the shared rule can
      # do the keyword probe; punctuation carries no word.
      prev_word = if word_char?(prev_char)
                    word_start = prev_idx
                    while word_start > 0 && word_char?(chr(src, word_start - 1))
                      word_start -= 1
                    end
                    word_string(src, word_start, prev_idx + 1)
                  else
                    ""
                  end

      before_prev = prev_idx > 0 ? chr(src, prev_idx - 1) : nil
      regex_context?(prev_char, prev_word, before_prev)
    end
  end
end
