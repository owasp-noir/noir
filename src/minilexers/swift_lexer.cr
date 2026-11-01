require "./masked_lexer"
require "../miniparsers/extraction_result_cache"

module Noir
  # SwiftLexer is a hand-rolled structural masking lexer for Swift source,
  # modelled on `Noir::PhpLexer`, `Noir::CSharpLexer`, and `Noir::ScalaLexer`.
  #
  # Swift routes and brace counting used to be performed line-by-line or with
  # ad-hoc regexes, causing:
  #   * Delimiters (`{`, `}`, `(`, `)`) in string literals and comments to truncate
  #     closures or corrupt group scopes.
  #   * Route-shaped literals in documentation or comments (e.g. `app.get("fake")`)
  #     to be falsely detected as endpoints.
  #   * Multi-line `"""` strings, raw strings (`#"..."#`, `##"..."##`), and nested
  #     block comments (`/* /* */ */`) to corrupt parser state across lines.
  #
  # This lexer performs a single linear pass that blanks every non-code region
  # (comments and string literal contents) to spaces while keeping newlines and
  # delimiters (`"`, `"""`, `#"`, `"#`, etc., `//`, `/*`, `*/`), and keeping code
  # inside string interpolations `\(` unmasked so braces inside interpolations
  # stay balanced.
  class SwiftLexer
    include MaskedLexer

    MAX_INTERPOLATION_DEPTH = 64

    @@memo = Hash(UInt64, SwiftLexer).new
    @@memo_mutex = Mutex.new

    ExtractionResultCache.register_clearer do
      @@memo_mutex.synchronize { @@memo.clear }
    end

    def self.for(source : String) : SwiftLexer
      key = ExtractionResultCache.source_fingerprint(source)
      ExtractionResultCache.fetch(@@memo, key, @@memo_mutex) do
        SwiftLexer.new(source)
      end
    end

    getter chars : Array(Char)
    @interp_depth : Int32
    @masked_lines : Array(String)?
    @masked_source : String?
    @code_lines : Array(String)?
    @code_source : String?

    def initialize(source : String)
      @chars = source.chars
      @size = @chars.size
      @masked = @chars.dup
      @spans = [] of Tuple(Symbol, Int32, Int32)
      @interp_depth = 0
      @skip_ranges = nil
      @masked_lines = nil
      @masked_source = nil
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
        elsif c == '"' || c == '#'
          i = dispatch_string(i)
        else
          i += 1
        end
      end
    end

    # Length of consecutive '#' characters starting at `start`.
    private def hash_run(start : Int32) : Int32
      h = 0
      while start + h < @size && @chars[start + h] == '#'
        h += 1
      end
      h
    end

    # Verifies whether `count` consecutive '#' characters appear starting at `start`,
    # and ensures they are not immediately followed by an additional '#'.
    private def check_hashes(start : Int32, count : Int32) : Bool
      return true if count == 0
      return false if start + count > @size
      (0...count).each do |k|
        return false if @chars[start + k] != '#'
      end
      if start + count < @size && @chars[start + count] == '#'
        return false
      end
      true
    end

    private def mask_line_comment(start : Int32) : Int32
      @masked[start] = '/'
      @masked[start + 1] = '/' if start + 1 < @size
      i = start + 2
      while i < @size && @chars[i] != '\n'
        @masked[i] = ' '
        i += 1
      end
      @spans << {:comment, start, i}
      i
    end

    # Swift block comments NEST: `/* /* */ */`. Track depth.
    private def mask_block_comment(start : Int32) : Int32
      @masked[start] = '/'
      @masked[start + 1] = '*' if start + 1 < @size
      depth = 1
      i = start + 2
      while i < @size && depth > 0
        c = @chars[i]
        nxt = i + 1 < @size ? @chars[i + 1] : '\0'

        if c == '/' && nxt == '*'
          depth += 1
          @masked[i] = ' '
          @masked[i + 1] = ' '
          i += 2
        elsif c == '*' && nxt == '/'
          depth -= 1
          if depth == 0
            @masked[i] = '*'
            @masked[i + 1] = '/'
            i += 2
            break
          else
            @masked[i] = ' '
            @masked[i + 1] = ' '
            i += 2
          end
        else
          @masked[i] = c == '\n' ? '\n' : ' '
          i += 1
        end
      end
      @spans << {:comment, start, i}
      i
    end

    private def dispatch_string(start : Int32) : Int32
      c = @chars[start]
      hashes = c == '#' ? hash_run(start) : 0
      quote_pos = start + hashes

      # If '#' is not followed by '"', it is an identifier/directive (e.g. #if, #selector)
      if quote_pos >= @size || @chars[quote_pos] != '"'
        return start + (hashes > 0 ? hashes : 1)
      end

      # Check for multi-line """
      is_multiline = quote_pos + 2 < @size && @chars[quote_pos + 1] == '"' && @chars[quote_pos + 2] == '"'
      if is_multiline
        mask_multiline_string(start, hashes)
      else
        mask_single_string(start, hashes)
      end
    end

    private def mask_single_string(start : Int32, hashes : Int32) : Int32
      # Delimiters kept
      hashes.times { |k| @masked[start + k] = '#' }
      @masked[start + hashes] = '"'

      i = start + hashes + 1
      span_start = start

      while i < @size
        c = @chars[i]

        # Single-line strings terminate at newline in Swift
        if c == '\n'
          @spans << {:string, span_start, i}
          return i
        end

        # Closing delimiter: " followed by `hashes` '#'
        if c == '"' && check_hashes(i + 1, hashes)
          @masked[i] = '"'
          hashes.times { |k| @masked[i + 1 + k] = '#' }
          finish = i + 1 + hashes
          @spans << {:string, span_start, finish}
          return finish
        end

        # Interpolation: \ followed by `hashes` '#' and '('
        if c == '\\' && check_hashes(i + 1, hashes) && (i + 1 + hashes < @size && @chars[i + 1 + hashes] == '(')
          if @interp_depth >= MAX_INTERPOLATION_DEPTH
            @masked[i] = ' '
            i += 1
            next
          end

          @masked[i] = '\\'
          hashes.times { |k| @masked[i + 1 + k] = '#' }
          @masked[i + 1 + hashes] = '('
          @spans << {:string, span_start, i + 2 + hashes}

          # Parse interpolation (code inside is unmasked)
          @interp_depth += 1
          i = scan_interpolation(i + 2 + hashes, hashes)
          @interp_depth -= 1
          span_start = i
          next
        end

        # Escape sequences
        if c == '\\'
          if hashes == 0
            @masked[i] = ' '
            if i + 1 < @size
              @masked[i + 1] = (@chars[i + 1] == '\n' ? '\n' : ' ')
              i += 2
            else
              i += 1
            end
            next
          else
            # In raw strings, only \ followed by `hashes` '#' escapes
            if check_hashes(i + 1, hashes)
              @masked[i] = ' '
              hashes.times { |k| @masked[i + 1 + k] = ' ' }
              esc_target = i + 1 + hashes
              if esc_target < @size
                @masked[esc_target] = (@chars[esc_target] == '\n' ? '\n' : ' ')
                i = esc_target + 1
              else
                i = esc_target
              end
              next
            else
              @masked[i] = ' '
              i += 1
              next
            end
          end
        end

        @masked[i] = ' '
        i += 1
      end

      @spans << {:string, span_start, i}
      i
    end

    private def mask_multiline_string(start : Int32, hashes : Int32) : Int32
      hashes.times { |k| @masked[start + k] = '#' }
      3.times { |k| @masked[start + hashes + k] = '"' }

      i = start + hashes + 3
      span_start = start

      while i < @size
        c = @chars[i]

        # Closing delimiter: """ followed by `hashes` '#'
        if c == '"' && i + 2 < @size && @chars[i + 1] == '"' && @chars[i + 2] == '"' && check_hashes(i + 3, hashes)
          3.times { |k| @masked[i + k] = '"' }
          hashes.times { |k| @masked[i + 3 + k] = '#' }
          finish = i + 3 + hashes
          @spans << {:string, span_start, finish}
          return finish
        end

        # Interpolation: \ followed by `hashes` '#' and '('
        if c == '\\' && check_hashes(i + 1, hashes) && (i + 1 + hashes < @size && @chars[i + 1 + hashes] == '(')
          if @interp_depth >= MAX_INTERPOLATION_DEPTH
            @masked[i] = ' '
            i += 1
            next
          end

          @masked[i] = '\\'
          hashes.times { |k| @masked[i + 1 + k] = '#' }
          @masked[i + 1 + hashes] = '('
          @spans << {:string, span_start, i + 2 + hashes}

          @interp_depth += 1
          i = scan_interpolation(i + 2 + hashes, hashes)
          @interp_depth -= 1
          span_start = i
          next
        end

        # Escape sequences
        if c == '\\'
          if hashes == 0
            @masked[i] = ' '
            if i + 1 < @size
              @masked[i + 1] = (@chars[i + 1] == '\n' ? '\n' : ' ')
              i += 2
            else
              i += 1
            end
            next
          else
            if check_hashes(i + 1, hashes)
              @masked[i] = ' '
              hashes.times { |k| @masked[i + 1 + k] = ' ' }
              esc_target = i + 1 + hashes
              if esc_target < @size
                @masked[esc_target] = (@chars[esc_target] == '\n' ? '\n' : ' ')
                i = esc_target + 1
              else
                i = esc_target
              end
              next
            else
              @masked[i] = ' '
              i += 1
              next
            end
          end
        end

        @masked[i] = c == '\n' ? '\n' : ' '
        i += 1
      end

      @spans << {:string, span_start, i}
      i
    end

    # Parses code inside an interpolation hole `\( ... )` (or `\#( ... )`).
    # Code inside is kept UNMASKED in `@masked`, including braces, closures, and method calls.
    # Delimiter ')' closing the hole is kept.
    private def scan_interpolation(start : Int32, outer_hashes : Int32) : Int32
      depth = 1
      i = start

      while i < @size && depth > 0
        c = @chars[i]
        nxt = i + 1 < @size ? @chars[i + 1] : '\0'

        if c == '/' && nxt == '/'
          i = mask_line_comment(i)
        elsif c == '/' && nxt == '*'
          i = mask_block_comment(i)
        elsif c == '"' || (c == '#' && (h = hash_run(i)) > 0 && i + h < @size && @chars[i + h] == '"')
          i = dispatch_string(i)
        elsif c == '('
          depth += 1
          @masked[i] = '('
          i += 1
        elsif c == ')'
          depth -= 1
          if depth == 0
            @masked[i] = ')'
            i += 1
            break
          else
            @masked[i] = ')'
            i += 1
          end
        else
          @masked[i] = c
          i += 1
        end
      end

      i
    end

    def masked_source : String
      @masked_source ||= @masked.join
    end

    def masked_lines : Array(String)
      @masked_lines ||= masked_source.lines
    end

    # Source with comments blanked to spaces, but string literals kept intact.
    def code_source : String
      @code_source ||= begin
        if @spans.none? { |(kind, _, _)| kind == :comment }
          @chars.join
        else
          chars = @chars.dup
          @spans.each do |(kind, start, finish)|
            next unless kind == :comment
            (start...finish).each do |idx|
              next if idx >= @size
              chars[idx] = ' ' unless chars[idx] == '\n' || chars[idx] == '\r'
            end
          end
          chars.join
        end
      end
    end

    def code_lines : Array(String)
      @code_lines ||= code_source.lines
    end
  end
end
