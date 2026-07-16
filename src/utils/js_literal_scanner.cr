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

    # Characters that can precede a regex literal (operators/punctuation expecting expression)
    REGEX_PRECEDING_CHARS = Set{'(', '[', '{', ',', ':', ';', '=', '!', '&', '|', '?', '+', '-', '*', '%', '<', '>', '~', '^'}

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

    # Try to skip a literal at the current position
    # Returns updated content string and position if a literal was skipped, nil otherwise
    def self.try_skip_literal(content : String, pos : Int32, accumulated : String) : NamedTuple(content: String, pos: Int32)?
      # Rebuild the rolling tail window the scan core keys regex detection
      # off from the caller-provided accumulated prefix.
      stripped = accumulated.rstrip
      window = (stripped.size > KEYWORD_WINDOW ? stripped[(stripped.size - KEYWORD_WINDOW)..] : stripped).chars
      pending_ws = [] of Char

      new_pos = nil.as(Int32?)
      appended = String.build do |io|
        new_pos = if single_byte?(content)
                    scan_literal(content.to_slice, content.size, pos, io, window, pending_ws)
                  else
                    scan_literal(content.chars, content.size, pos, io, window, pending_ws)
                  end
      end
      end_pos = new_pos
      return unless end_pos

      {content: appended.empty? ? accumulated : accumulated + appended, pos: end_pos}
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
      # Only reached through the `single_byte?` fast path, so every byte is
      # a valid single-byte char.
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

      result = String.build do |io|
        while pos < size && paren_depth > 0
          # Try to skip literals
          if skip_pos = scan_literal(src, size, pos, io, window, pending_ws)
            pos = skip_pos
            next
          end

          char = chr(src, pos)

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

    # Skips (and where applicable, appends) one comment/string/template/
    # regex literal starting at `pos`. Returns the resume position, or nil
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
        emit(io, window, pending_ws, char)
        pos += 1
        while pos < size && chr(src, pos) != '`'
          if chr(src, pos) == '\\' && pos + 1 < size
            emit(io, window, pending_ws, chr(src, pos))
            pos += 1
          end
          emit(io, window, pending_ws, chr(src, pos)) if pos < size
          pos += 1
        end
        emit(io, window, pending_ws, '`') if pos < size && chr(src, pos) == '`'
        pos += 1
        return pos
      end

      # Skip regex literals
      if char == '/' && looks_like_regex?(window)
        emit(io, window, pending_ws, char)
        pos += 1
        in_char_class = false
        while pos < size
          rc = chr(src, pos)
          break if rc == '/' && !in_char_class
          if rc == '\\' && pos + 1 < size
            emit(io, window, pending_ws, rc)
            pos += 1
            emit(io, window, pending_ws, chr(src, pos)) if pos < size
            pos += 1
          elsif rc == '[' && !in_char_class
            in_char_class = true
            emit(io, window, pending_ws, rc)
            pos += 1
          elsif rc == ']' && in_char_class
            in_char_class = false
            emit(io, window, pending_ws, rc)
            pos += 1
          else
            emit(io, window, pending_ws, rc)
            pos += 1
          end
        end
        emit(io, window, pending_ws, '/') if pos < size && chr(src, pos) == '/'
        pos += 1
        # Skip regex flags
        while pos < size && chr(src, pos).in?('g', 'i', 'm', 's', 'u', 'y', 'd')
          emit(io, window, pending_ws, chr(src, pos))
          pos += 1
        end
        return pos
      end

      nil
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

    # Determine if '/' at current position likely starts a regex literal.
    # `window` is the rstrip'd tail of the scanned output — enough for both
    # the last-char probe and the keyword `ends_with?` probe.
    private def self.looks_like_regex?(window : Array(Char)) : Bool
      last_char = window.last?
      return true if last_char && REGEX_PRECEDING_CHARS.includes?(last_char)

      REGEX_PRECEDING_KEYWORDS.each do |keyword|
        return true if window_ends_with?(window, keyword)
      end

      false
    end

    private def self.window_ends_with?(window : Array(Char), keyword : String) : Bool
      return false if window.size < keyword.size
      offset = window.size - keyword.size
      keyword.each_char_with_index do |ch, i|
        return false unless window[offset + i] == ch
      end
      true
    end

    private def self.find_matching_impl(src, open_idx : Int32, open_char : Char, close_char : Char) : Int32?
      size = src.size
      count = 1
      idx = open_idx + 1

      while idx < size && count > 0
        # Try to skip literals
        if skip_idx = simple_literal_end(src, size, idx)
          idx = skip_idx
          next
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

    # Simplified literal skip that doesn't accumulate content - just returns new position
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
      if char == '`'
        pos += 1
        while pos < size && chr(src, pos) != '`'
          if chr(src, pos) == '\\' && pos + 1 < size
            pos += 2
          else
            pos += 1
          end
        end
        pos += 1
        return pos
      end

      # Skip regex literals (use simple heuristic based on previous char)
      if char == '/'
        # Look back for regex-preceding context
        prev_idx = pos - 1
        while prev_idx > 0 && chr(src, prev_idx).whitespace?
          prev_idx -= 1
        end
        prev_char = prev_idx >= 0 ? chr(src, prev_idx) : '('

        # Check for punctuation or extract previous word for keyword check
        is_regex = REGEX_PRECEDING_CHARS.includes?(prev_char)

        unless is_regex
          word_end = prev_idx + 1
          word_start = prev_idx
          while word_start > 0 && (chr(src, word_start - 1).alphanumeric? || chr(src, word_start - 1) == '_')
            word_start -= 1
          end
          if word_start < word_end
            prev_word = word_string(src, word_start, word_end)
            is_regex = REGEX_PRECEDING_KEYWORDS.includes?(prev_word)
          end
        end

        if is_regex
          pos += 1
          in_char_class = false
          while pos < size
            break if chr(src, pos) == '/' && !in_char_class
            if chr(src, pos) == '\\' && pos + 1 < size
              pos += 2
            elsif chr(src, pos) == '[' && !in_char_class
              in_char_class = true
              pos += 1
            elsif chr(src, pos) == ']' && in_char_class
              in_char_class = false
              pos += 1
            else
              pos += 1
            end
          end
          pos += 1 if pos < size
          # Skip regex flags
          while pos < size && chr(src, pos).in?('g', 'i', 'm', 's', 'u', 'y', 'd')
            pos += 1
          end
          return pos
        end
      end

      nil
    end
  end
end
