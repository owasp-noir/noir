require "../models/endpoint"
require "./callee_extractor_base"

module Noir::PhpCalleeExtractor
  extend self
  include Noir::CalleeExtractorBase

  RESERVED = Set{
    "array", "catch", "class", "clone", "declare", "die", "echo",
    "elseif", "empty", "eval", "exit", "fn", "for", "foreach",
    "function", "global", "if", "include", "include_once", "isset",
    "list", "match", "print", "require", "require_once", "return",
    "static", "switch", "throw", "trait", "try", "unset", "use", "while",
  }

  CLASS_PROPERTY_CALL_REGEX = /(\\?[A-Za-z_]\w*(?:\\[A-Za-z_]\w*)*::\$\w+(?:\s*->\s*[A-Za-z_]\w*\s*(?:\(\s*\))?)*\s*->\s*[A-Za-z_]\w*)\s*\(/
  OBJECT_CALL_REGEX         = /(?<!:)(\$[A-Za-z_]\w*(?:\s*->\s*[A-Za-z_]\w*\s*(?:\(\s*\))?)*\s*->\s*[A-Za-z_]\w*)\s*\(/
  STATIC_CALL_REGEX         = /(\\?[A-Za-z_]\w*(?:\\[A-Za-z_]\w*)*(?:::[A-Za-z_]\w*)+)\s*\(/
  BARE_CALL_REGEX           = /(?<![>\w:$\\])(\\?[A-Za-z_]\w*(?:\\[A-Za-z_]\w*)*)\s*\(/

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry

    in_block_comment = false

    body.lines.each_with_index do |line, index|
      sanitized, in_block_comment = sanitize_line(line, in_block_comment)
      scan_line(sanitized, file_path, start_line + index, entries)
    end

    dedup_entries(entries)
  end

  private def scan_line(line : String, file_path : String, line_number : Int32, entries : Array(Entry))
    line.scan(CLASS_PROPERTY_CALL_REGEX) do |match|
      name = normalize_object_call(match[1])
      next if skip_callee?(name)

      entries << {name, file_path, line_number}
    end

    line.scan(OBJECT_CALL_REGEX) do |match|
      name = normalize_object_call(match[1])
      next if skip_callee?(name)

      entries << {name, file_path, line_number}
    end

    line.scan(STATIC_CALL_REGEX) do |match|
      name = normalize_static_call(match[1])
      next if skip_callee?(name)

      entries << {name, file_path, line_number}
    end

    line.scan(BARE_CALL_REGEX) do |match|
      name = match[1]
      next if declaration_name?(line, match.begin(1))
      next if skip_callee?(name)

      entries << {name, file_path, line_number}
    end
  end

  private def declaration_name?(line : String, name_start : Int32?) : Bool
    return false unless name_start

    line[0...name_start].match(/\bfunction\s*&?\s*$/) ? true : false
  end

  private def normalize_object_call(name : String) : String
    name.gsub(/\s+/, "")
  end

  private def normalize_static_call(name : String) : String
    name.gsub(/\s+/, "")
  end

  private def skip_callee?(name : String) : Bool
    return true if name.empty?
    return false if name.includes?("->") || name.includes?("::")

    RESERVED.includes?(name.downcase)
  end

  def strip_comment(line : String) : String
    sanitized, _ = sanitize_line(line, false)
    sanitized
  end

  # ASCII byte values for the delimiters scanned below. All < 0x80, so a
  # UTF-8 multi-byte sequence (bytes >= 0x80) never collides with them.
  private BYTE_NEWLINE   = '\n'.ord.to_u8
  private BYTE_STAR      = '*'.ord.to_u8
  private BYTE_SLASH     = '/'.ord.to_u8
  private BYTE_HASH      = '#'.ord.to_u8
  private BYTE_BACKSLASH = '\\'.ord.to_u8
  private BYTE_DQUOTE    = '"'.ord.to_u8
  private BYTE_SQUOTE    = '\''.ord.to_u8
  private BYTE_SPACE     = ' '.ord.to_u8

  # Blank out string literals and comments so the call-pattern regexes only
  # see executable code. Scans the raw byte buffer for O(1) positional
  # access — `String#[](Int)` is O(n) on multi-byte strings, which made a
  # single long CJK/escaped line (e.g. CRMEB's half-megabyte SQL seed
  # literal) cost O(n^2). String/comment bytes are replaced with spaces;
  # code bytes (including any multi-byte ones outside strings) are copied
  # verbatim so the result stays valid UTF-8.
  private def sanitize_line(line : String, in_block_comment : Bool) : Tuple(String, Bool)
    bytes = line.to_slice
    size = bytes.size
    sanitized = String.build do |io|
      in_string = false
      escaped = false
      quote = 0_u8
      index = 0

      while index < size
        char = bytes[index]
        next_char = index + 1 < size ? bytes[index + 1] : 0_u8

        if in_block_comment
          if char == BYTE_STAR && next_char == BYTE_SLASH
            io << "  "
            in_block_comment = false
            index += 2
          else
            io << ' '
            index += 1
          end
        elsif in_string
          io << ' '
          if escaped
            escaped = false
          elsif char == BYTE_BACKSLASH
            escaped = true
          elsif char == quote
            in_string = false
          end
          index += 1
        elsif char == BYTE_SLASH && next_char == BYTE_STAR
          io << "  "
          in_block_comment = true
          index += 2
        elsif (char == BYTE_SLASH && next_char == BYTE_SLASH) || char == BYTE_HASH
          (size - index).times { io.write_byte(BYTE_SPACE) }
          index = size
        elsif char == BYTE_DQUOTE || char == BYTE_SQUOTE
          io << ' '
          in_string = true
          quote = char
          index += 1
        else
          io.write_byte(char)
          index += 1
        end
      end
    end

    {sanitized, in_block_comment}
  end
end
