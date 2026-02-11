module Noir
  # JSLiteralScanner provides utilities for scanning JavaScript source code
  # while properly skipping string literals, comments, template literals, and regex.
  # This ensures parenthesis/brace matching doesn't get confused by literals.
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
    REGEX_PRECEDING_CHARS = ['(', '[', '{', ',', ':', ';', '=', '!', '&', '|', '?', '+', '-', '*', '%', '<', '>', '~', '^']

    # Extract content between parentheses while skipping literals
    # Returns the content inside the parentheses (not including the parens)
    def self.extract_paren_content(content : String, start_pos : Int32) : ScanResult?
      return unless start_pos < content.size

      result = ""
      paren_depth = 1
      pos = start_pos

      while pos < content.size && paren_depth > 0
        char = content[pos]

        # Try to skip literals
        skip_result = try_skip_literal(content, pos, result)
        if skip_result
          result = skip_result[:content]
          pos = skip_result[:pos]
          next
        end

        # Track parentheses depth
        if char == '('
          paren_depth += 1
        elsif char == ')'
          paren_depth -= 1
          break if paren_depth == 0
        end

        result += char
        pos += 1
      end

      ScanResult.new(result, pos)
    end

    # Try to skip a literal at the current position
    # Returns updated content string and position if a literal was skipped, nil otherwise
    def self.try_skip_literal(content : String, pos : Int32, accumulated : String) : NamedTuple(content: String, pos: Int32)?
      char = content[pos]

      # Skip single-line comments
      if char == '/' && pos + 1 < content.size && content[pos + 1] == '/'
        while pos < content.size && content[pos] != '\n'
          pos += 1
        end
        return {content: accumulated, pos: pos}
      end

      # Skip multi-line comments
      if char == '/' && pos + 1 < content.size && content[pos + 1] == '*'
        pos += 2
        while pos + 1 < content.size && !(content[pos] == '*' && content[pos + 1] == '/')
          pos += 1
        end
        pos += 2 if pos + 1 < content.size
        return {content: accumulated, pos: pos}
      end

      # Skip string literals (single/double quotes)
      if char == '"' || char == '\''
        result = accumulated + char
        quote = char
        pos += 1
        while pos < content.size && content[pos] != quote
          if content[pos] == '\\' && pos + 1 < content.size
            result += content[pos]
            pos += 1
          end
          result += content[pos] if pos < content.size
          pos += 1
        end
        result += content[pos] if pos < content.size && content[pos] == quote
        pos += 1
        return {content: result, pos: pos}
      end

      # Skip template literals
      if char == '`'
        result = accumulated + char
        pos += 1
        while pos < content.size && content[pos] != '`'
          if content[pos] == '\\' && pos + 1 < content.size
            result += content[pos]
            pos += 1
          end
          result += content[pos] if pos < content.size
          pos += 1
        end
        result += content[pos] if pos < content.size && content[pos] == '`'
        pos += 1
        return {content: result, pos: pos}
      end

      # Skip regex literals
      if char == '/' && looks_like_regex?(accumulated, content, pos)
        result = accumulated + char
        pos += 1
        in_char_class = false
        while pos < content.size
          rc = content[pos]
          break if rc == '/' && !in_char_class
          if rc == '\\' && pos + 1 < content.size
            result += rc
            pos += 1
            result += content[pos] if pos < content.size
            pos += 1
          elsif rc == '[' && !in_char_class
            in_char_class = true
            result += rc
            pos += 1
          elsif rc == ']' && in_char_class
            in_char_class = false
            result += rc
            pos += 1
          else
            result += rc
            pos += 1
          end
        end
        result += content[pos] if pos < content.size && content[pos] == '/'
        pos += 1
        # Skip regex flags
        while pos < content.size && content[pos].in?('g', 'i', 'm', 's', 'u', 'y', 'd')
          result += content[pos]
          pos += 1
        end
        return {content: result, pos: pos}
      end

      nil
    end

    # Determine if '/' at current position likely starts a regex literal
    private def self.looks_like_regex?(accumulated : String, content : String, pos : Int32) : Bool
      # Check last non-whitespace char in accumulated content
      last_char = accumulated.rstrip.chars.last?
      return true if last_char && REGEX_PRECEDING_CHARS.includes?(last_char)

      # Check if preceded by keyword
      stripped = accumulated.rstrip
      REGEX_PRECEDING_KEYWORDS.each do |keyword|
        return true if stripped.ends_with?(keyword)
      end

      false
    end

    # Find matching closing brace, skipping literals
    def self.find_matching_brace(content : String, open_brace_idx : Int32) : Int32?
      brace_count = 1
      idx = open_brace_idx + 1

      while idx < content.size && brace_count > 0
        # Try to skip literals (use empty string since we don't need accumulated content)
        skip_result = try_skip_literal_simple(content, idx)
        if skip_result
          idx = skip_result
          next
        end

        case content[idx]
        when '{'
          brace_count += 1
        when '}'
          brace_count -= 1
        end
        idx += 1

        return idx - 1 if brace_count == 0
      end

      nil
    end

    # Find matching closing paren, skipping literals
    def self.find_matching_paren(content : String, open_paren_idx : Int32) : Int32?
      paren_count = 1
      idx = open_paren_idx + 1

      while idx < content.size && paren_count > 0
        # Try to skip literals
        skip_result = try_skip_literal_simple(content, idx)
        if skip_result
          idx = skip_result
          next
        end

        case content[idx]
        when '('
          paren_count += 1
        when ')'
          paren_count -= 1
        end
        idx += 1

        return idx - 1 if paren_count == 0
      end

      nil
    end

    # Simplified literal skip that doesn't accumulate content - just returns new position
    private def self.try_skip_literal_simple(content : String, pos : Int32) : Int32?
      char = content[pos]

      # Skip single-line comments
      if char == '/' && pos + 1 < content.size && content[pos + 1] == '/'
        while pos < content.size && content[pos] != '\n'
          pos += 1
        end
        return pos
      end

      # Skip multi-line comments
      if char == '/' && pos + 1 < content.size && content[pos + 1] == '*'
        pos += 2
        while pos + 1 < content.size && !(content[pos] == '*' && content[pos + 1] == '/')
          pos += 1
        end
        pos += 2 if pos + 1 < content.size
        return pos
      end

      # Skip string literals
      if char == '"' || char == '\''
        quote = char
        pos += 1
        while pos < content.size && content[pos] != quote
          if content[pos] == '\\' && pos + 1 < content.size
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
        while pos < content.size && content[pos] != '`'
          if content[pos] == '\\' && pos + 1 < content.size
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
        while prev_idx > 0 && content[prev_idx].whitespace?
          prev_idx -= 1
        end
        prev_char = prev_idx >= 0 ? content[prev_idx] : '('

        # Check for punctuation or extract previous word for keyword check
        is_regex = REGEX_PRECEDING_CHARS.includes?(prev_char)

        unless is_regex
          word_end = prev_idx + 1
          word_start = prev_idx
          while word_start > 0 && (content[word_start - 1].alphanumeric? || content[word_start - 1] == '_')
            word_start -= 1
          end
          if word_start < word_end
            prev_word = content[word_start...word_end]
            is_regex = REGEX_PRECEDING_KEYWORDS.includes?(prev_word)
          end
        end

        if is_regex
          pos += 1
          in_char_class = false
          while pos < content.size
            break if content[pos] == '/' && !in_char_class
            if content[pos] == '\\' && pos + 1 < content.size
              pos += 2
            elsif content[pos] == '[' && !in_char_class
              in_char_class = true
              pos += 1
            elsif content[pos] == ']' && in_char_class
              in_char_class = false
              pos += 1
            else
              pos += 1
            end
          end
          pos += 1 if pos < content.size
          # Skip regex flags
          while pos < content.size && content[pos].in?('g', 'i', 'm', 's', 'u', 'y', 'd')
            pos += 1
          end
          return pos
        end
      end

      nil
    end
  end
end
