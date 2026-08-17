module Noir
  # Character-preserving masks over Kotlin source text.
  #
  # Both masks replace every masked-out character with a single space and
  # keep every newline, so the result lines up with the original *by
  # character*: `masked[i]` describes `source[i]`, `masked.lines[n]` is
  # exactly as long as `source.lines[n]`, and a `Regex::MatchData#end`
  # taken on the masked copy can be used to slice the raw text. Callers
  # depend on that to gate a line scan on the masked copy while reading
  # the real value out of the raw source.
  #
  # One space per *character*, not per byte: Crystal's `String#[]` and
  # `MatchData#begin/#end` are char-indexed while the scanner walks bytes,
  # so emitting one space per byte made every offset after a non-ASCII
  # comment (a CJK line above a route, an accented author name) drift by
  # the number of continuation bytes and over-trimmed the raw line.
  module KotlinSourceMask
    extend self

    # Comments blanked, string literals kept verbatim. Use this to run a
    # line regex that has to read a literal value — `const val PATH =
    # "/mcp"` — without also harvesting a commented-out declaration.
    def code_only(source : String) : String
      mask(source, mask_strings: false)
    end

    # Comments *and* string-literal contents blanked. Use this for
    # structural work — brace counting, delimiter matching, deciding
    # whether a call site is real code — where a `{` or a `(` inside a
    # string or a comment must not count.
    def visible(source : String) : String
      mask(source, mask_strings: true)
    end

    SLASH        = '/'.ord.to_u8
    STAR         = '*'.ord.to_u8
    DOUBLE_QUOTE = '"'.ord.to_u8
    SINGLE_QUOTE = '\''.ord.to_u8
    BACKSLASH    = '\\'.ord.to_u8
    NEWLINE      = '\n'.ord.to_u8
    SPACE        = ' '.ord.to_u8

    # UTF-8 continuation bytes (`10xxxxxx`) carry no character of their
    # own, so they contribute no space to the mask.
    private def continuation?(byte : UInt8) : Bool
      (byte & 0xC0) == 0x80
    end

    private def blank(io : IO, byte : UInt8)
      return if continuation?(byte)
      io.write_byte(byte == NEWLINE ? NEWLINE : SPACE)
    end

    private def mask(source : String, mask_strings : Bool) : String
      bytes = source.to_slice
      mode = :code
      quote = 0_u8
      raw_string = false
      escaped = false
      i = 0

      String.build(source.bytesize) do |io|
        while i < bytes.size
          byte = bytes[i]

          case mode
          when :line_comment
            if byte == NEWLINE
              io.write_byte(byte)
              mode = :code
            else
              blank(io, byte)
            end
            i += 1
          when :block_comment
            if byte == NEWLINE
              io.write_byte(byte)
              i += 1
            elsif i + 1 < bytes.size && byte == STAR && bytes[i + 1] == SLASH
              io.write_byte(SPACE)
              io.write_byte(SPACE)
              i += 2
              mode = :code
            else
              blank(io, byte)
              i += 1
            end
          when :string
            if raw_string && i + 2 < bytes.size && byte == DOUBLE_QUOTE && bytes[i + 1] == DOUBLE_QUOTE && bytes[i + 2] == DOUBLE_QUOTE
              3.times { io.write_byte(mask_strings ? SPACE : DOUBLE_QUOTE) }
              i += 3
              mode = :code
              raw_string = false
            elsif !raw_string && byte == quote && !escaped
              io.write_byte(mask_strings ? SPACE : byte)
              i += 1
              mode = :code
            else
              if mask_strings
                blank(io, byte)
              else
                io.write_byte(byte)
              end
              if raw_string
                i += 1
              elsif escaped
                escaped = false
                i += 1
              else
                escaped = byte == BACKSLASH
                i += 1
              end
            end
          else
            if i + 1 < bytes.size && byte == SLASH && bytes[i + 1] == SLASH
              io.write_byte(SPACE)
              io.write_byte(SPACE)
              i += 2
              mode = :line_comment
            elsif i + 1 < bytes.size && byte == SLASH && bytes[i + 1] == STAR
              io.write_byte(SPACE)
              io.write_byte(SPACE)
              i += 2
              mode = :block_comment
            elsif i + 2 < bytes.size && byte == DOUBLE_QUOTE && bytes[i + 1] == DOUBLE_QUOTE && bytes[i + 2] == DOUBLE_QUOTE
              3.times { io.write_byte(mask_strings ? SPACE : DOUBLE_QUOTE) }
              i += 3
              mode = :string
              raw_string = true
            elsif byte == DOUBLE_QUOTE || byte == SINGLE_QUOTE
              io.write_byte(mask_strings ? SPACE : byte)
              quote = byte
              raw_string = false
              escaped = false
              i += 1
              mode = :string
            else
              io.write_byte(byte)
              i += 1
            end
          end
        end
      end
    end
  end
end
