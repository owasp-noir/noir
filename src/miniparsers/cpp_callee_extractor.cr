require "../models/endpoint"
require "./callee_extractor_base"

module Noir::CppCalleeExtractor
  extend self
  include Noir::CalleeExtractorBase

  RESERVED = Set{
    "alignas", "alignof", "and", "and_eq", "asm", "auto", "bitand",
    "bitor", "bool", "break", "case", "catch", "char", "char8_t",
    "char16_t", "char32_t", "class", "compl", "concept", "const",
    "const_cast", "consteval", "constexpr", "constinit", "continue",
    "co_await", "co_return", "co_yield", "decltype", "default", "delete", "do",
    "double", "dynamic_cast", "else", "enum", "explicit", "export",
    "extern", "false", "float", "for", "friend", "goto", "if",
    "inline", "int", "long", "mutable", "namespace", "new", "noexcept",
    "not", "not_eq", "nullptr", "operator", "or", "or_eq", "private",
    "protected", "public", "register", "reinterpret_cast", "requires",
    "return", "short", "signed", "sizeof", "static", "static_assert",
    "static_cast", "struct", "switch", "template", "this", "thread_local",
    "throw", "true", "try", "typedef", "typeid", "typename", "union",
    "unsigned", "using", "virtual", "void", "volatile", "wchar_t", "while",
    "xor", "xor_eq",
  }

  ROUTE_MACROS = Set{
    "CROW_ROUTE", "CROW_BP_ROUTE", "PATH_ADD", "ADD_METHOD_TO",
    "PATH_LIST_BEGIN", "PATH_LIST_END", "METHOD_LIST_BEGIN", "METHOD_LIST_END",
  }

  SCOPED_CALL_REGEX = /((?:[A-Za-z_][A-Za-z0-9_]*\s*::\s*)+[A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^;\n{}]*>)?\s*\(/
  MEMBER_CALL_REGEX = /([A-Za-z_][A-Za-z0-9_]*(?:\s*(?:->|\.)\s*[A-Za-z_][A-Za-z0-9_]*)+)\s*(?:<[^;\n{}]*>)?\s*\(/
  BARE_CALL_REGEX   = /(?<![A-Za-z0-9_:.>])([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^;\n{}]*>)?\s*\(/

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry
    in_block_comment = false
    raw_terminator = nil.as(String?)

    body.each_line.with_index do |line, index|
      stripped, in_block_comment, raw_terminator = strip_non_code_with_state(line, in_block_comment, raw_terminator)
      scan_line(stripped, file_path, start_line + index, entries)
    end

    dedup_entries(entries)
  end

  def extract_block_after(source : String, start_index : Int32, limit : Int32 = source.bytesize) : Tuple(String, Int32)?
    open_index = find_next_code_char(source, '{', start_index, limit)
    return unless open_index

    close_index = find_matching_delimiter(source, open_index, '{', '}', limit)
    return unless close_index

    # open_index/close_index are BYTE offsets (the scanners use byte_at); slice
    # by bytes — char-indexing here corrupts/crashes on multi-byte UTF-8 source.
    {source.byte_slice(open_index + 1, close_index - open_index - 1), line_number_for(source, open_index)}
  end

  def extract_lambda_block_after(source : String, start_index : Int32, limit : Int32 = source.bytesize) : Tuple(String, Int32)?
    open_index = find_next_code_char(source, '{', start_index, limit)
    return unless open_index
    return if find_next_code_char(source, ';', start_index, open_index)
    return unless source.byte_slice(start_index, open_index - start_index).includes?('[')

    close_index = find_matching_delimiter(source, open_index, '{', '}', limit)
    return unless close_index

    {source.byte_slice(open_index + 1, close_index - open_index - 1), line_number_for(source, open_index)}
  end

  def find_next_code_char(source : String, target : Char, start_index : Int32, limit : Int32 = source.bytesize) : Int32?
    i = start_index
    while i < limit
      char = source.byte_at(i).unsafe_chr
      case char
      when '"'
        i = skip_string(source, i, limit)
      when '\''
        i = skip_char_literal(source, i, limit)
      when '/'
        next_char = i + 1 < limit ? source.byte_at(i + 1).unsafe_chr : '\0'
        if next_char == '/'
          i = skip_line_comment(source, i, limit)
        elsif next_char == '*'
          i = skip_block_comment(source, i, limit)
        elsif char == target
          return i
        end
      else
        return i if char == target
      end
      i += 1
    end

    nil
  end

  def find_matching_delimiter(source : String,
                              index : Int32,
                              open_char : Char,
                              close_char : Char,
                              limit : Int32 = source.bytesize) : Int32?
    depth = 0
    i = index

    while i < limit
      char = source.byte_at(i).unsafe_chr
      case char
      when '"'
        i = skip_string(source, i, limit)
      when '\''
        i = skip_char_literal(source, i, limit)
      when '/'
        next_char = i + 1 < limit ? source.byte_at(i + 1).unsafe_chr : '\0'
        if next_char == '/'
          i = skip_line_comment(source, i, limit)
        elsif next_char == '*'
          i = skip_block_comment(source, i, limit)
        end
      when open_char
        depth += 1
      when close_char
        depth -= 1
        return i if depth == 0
      end
      i += 1
    end

    nil
  end

  def line_number_for(source : String, index : Int32) : Int32
    1 + source.to_slice[0, index].count('\n'.ord.to_u8)
  end

  # Returns a copy of `source` with every `//` and `/* */` comment replaced by
  # spaces. String/char literals are preserved verbatim and newlines are kept,
  # so byte offsets and line numbers stay identical to the original. This lets
  # macro/route scanners run without matching commented-out (or documentation)
  # code. ASCII-oriented, matching the rest of the offset handling here.
  def strip_comments(source : String) : String
    unless source.includes?("//") || source.includes?("/*")
      return source
    end

    bytes = source.to_slice.dup
    size = bytes.size
    ptr = bytes.to_unsafe
    i = 0

    while i < size
      char = ptr[i].unsafe_chr

      if char == '"' && (delimiter = raw_string_delimiter(source, i, size))
        # Comments are only blanked at or before `i`, so reading ahead in the
        # untouched `source` and in `bytes` is equivalent here.
        i = skip_raw_string(source, i, size, delimiter) + 1
      elsif char == '\'' && digit_separator?(source, i)
        i += 1
      elsif char == '"' || char == '\''
        quote = char
        i += 1
        while i < size
          c = ptr[i].unsafe_chr
          if c == '\\'
            i += 2
            next
          elsif c == quote
            break
          end
          i += 1
        end
        i += 1
      elsif char == '/' && i + 1 < size && ptr[i + 1].unsafe_chr == '/'
        while i < size && ptr[i].unsafe_chr != '\n'
          ptr[i] = ' '.ord.to_u8
          i += 1
        end
      elsif char == '/' && i + 1 < size && ptr[i + 1].unsafe_chr == '*'
        ptr[i] = ' '.ord.to_u8
        ptr[i + 1] = ' '.ord.to_u8
        i += 2
        while i < size
          if ptr[i].unsafe_chr == '*' && i + 1 < size && ptr[i + 1].unsafe_chr == '/'
            ptr[i] = ' '.ord.to_u8
            ptr[i + 1] = ' '.ord.to_u8
            i += 2
            break
          end
          ptr[i] = ' '.ord.to_u8 unless ptr[i].unsafe_chr == '\n'
          i += 1
        end
      else
        i += 1
      end
    end

    String.new(bytes)
  end

  private def scan_line(line : String, file_path : String, line_number : Int32, entries : Array(Entry))
    return unless line.includes?('(')
    candidates = [] of Tuple(Int32, String)

    line.scan(SCOPED_CALL_REGEX) do |match|
      candidates << {match.begin(1) || 0, normalize_name(match[1])}
    end

    line.scan(MEMBER_CALL_REGEX) do |match|
      candidates << {match.begin(1) || 0, normalize_name(match[1])}
    end

    line.scan(BARE_CALL_REGEX) do |match|
      candidates << {match.begin(1) || 0, match[1]}
    end

    candidates.sort_by! { |position, _| position }
    candidates.each do |_, name|
      next if skip_callee?(name)

      entries << {name, file_path, line_number}
    end
  end

  private def normalize_name(name : String) : String
    name.gsub(/\s+/, "")
  end

  private def skip_callee?(name : String) : Bool
    return true if name.empty?
    return true if ROUTE_MACROS.includes?(name)

    last = name.split("::").last.split("->").last.split('.').last
    RESERVED.includes?(last) || ROUTE_MACROS.includes?(last)
  end

  private def strip_non_code_with_state(line : String,
                                        in_block_comment : Bool,
                                        raw_terminator : String?) : Tuple(String, Bool, String?)
    bytesize = line.bytesize
    ptr = line.to_unsafe
    in_string = false
    in_char = false
    escaped = false
    index = 0
    stripped = String::Builder.new(bytesize)

    # A raw string opened on an earlier line runs until its `)delim"`; nothing
    # before that is code, however many quotes or braces it contains.
    if pending = raw_terminator
      closed = find_bytes(line, pending, 0, bytesize)
      return {"", in_block_comment, pending} unless closed
      index = closed + pending.bytesize
      raw_terminator = nil
    end

    while index < bytesize
      byte = ptr[index]
      char = byte.unsafe_chr

      if in_block_comment
        if char == '*' && index + 1 < bytesize && ptr[index + 1].unsafe_chr == '/'
          in_block_comment = false
          index += 1
        end
      elsif in_string
        if escaped
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif char == '"'
          in_string = false
        end
      elsif in_char
        if escaped
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif char == '\''
          in_char = false
        end
      elsif char == '"' && (delimiter = raw_string_delimiter(line, index, bytesize))
        terminator = ")#{delimiter}\""
        body_start = index + delimiter.bytesize + 2
        if closed = find_bytes(line, terminator, body_start, bytesize)
          index = closed + terminator.bytesize
          next
        end
        raw_terminator = terminator
        break
      elsif char == '"'
        in_string = true
      elsif char == '\'' && !digit_separator?(line, index)
        in_char = true
      elsif char == '/' && index + 1 < bytesize && ptr[index + 1].unsafe_chr == '/'
        break
      elsif char == '/' && index + 1 < bytesize && ptr[index + 1].unsafe_chr == '*'
        in_block_comment = true
        index += 1
      else
        stripped.write_byte(byte)
      end

      index += 1
    end

    {stripped.to_s, in_block_comment, raw_terminator}
  end

  private def find_bytes(source : String, needle : String, start_index : Int32, limit : Int32) : Int32?
    size = needle.bytesize
    index = start_index

    while index + size <= limit
      return index if bytes_match?(source, index, needle)
      index += 1
    end

    nil
  end

  private def skip_string(source : String, index : Int32, limit : Int32) : Int32
    if delimiter = raw_string_delimiter(source, index, limit)
      return skip_raw_string(source, index, limit, delimiter)
    end

    i = index + 1
    escaping = false

    while i < limit
      char = source.byte_at(i).unsafe_chr
      if escaping
        escaping = false
      elsif char == '\\'
        escaping = true
      elsif char == '"'
        return i
      end
      i += 1
    end

    limit - 1
  end

  # A raw string literal (`R"(...)"`, `R"tag(...)tag"`, optionally prefixed
  # `u8`/`L`/`u`/`U`) ends only at its exact `)delim"` terminator. Its body may
  # hold unbalanced quotes, braces and newlines — that is the point of the
  # form — so the ordinary quote scanner desynchronizes on it. Returns the
  # d-char delimiter (possibly empty) when `index` opens a raw string.
  private def raw_string_delimiter(source : String, index : Int32, limit : Int32) : String?
    return unless raw_string_prefix?(source, index)

    i = index + 1
    # At most 16 d-chars, then the mandatory `(`.
    stop = Math.min(limit, index + 18)
    delimiter = String::Builder.new

    while i < stop
      char = source.byte_at(i).unsafe_chr
      return delimiter.to_s if char == '('
      return if char == ')' || char == '\\' || char == '"' || char.ascii_whitespace?
      delimiter << char
      i += 1
    end

    nil
  end

  # Returns the index of the closing `"`, matching `skip_string`'s contract.
  # An unterminated raw string degrades to the end of the scanned range.
  private def skip_raw_string(source : String, index : Int32, limit : Int32, delimiter : String) : Int32
    terminator = ")#{delimiter}\""
    size = terminator.bytesize
    i = index + delimiter.bytesize + 2

    while i + size <= limit
      return i + size - 1 if bytes_match?(source, i, terminator)
      i += 1
    end

    limit - 1
  end

  private def raw_string_prefix?(source : String, index : Int32) : Bool
    return false if index <= 0
    return false unless source.byte_at(index - 1).unsafe_chr == 'R'

    start = index - 1
    if start >= 2 && source.byte_at(start - 2).unsafe_chr == 'u' && source.byte_at(start - 1).unsafe_chr == '8'
      start -= 2
    elsif start >= 1 && {'L', 'u', 'U'}.includes?(source.byte_at(start - 1).unsafe_chr)
      start -= 1
    end

    return true if start == 0
    !identifier_byte?(source.byte_at(start - 1).unsafe_chr)
  end

  private def bytes_match?(source : String, index : Int32, needle : String) : Bool
    return false if index + needle.bytesize > source.bytesize

    offset = index
    needle.each_byte do |byte|
      return false unless source.byte_at(offset) == byte
      offset += 1
    end
    true
  end

  private def identifier_byte?(char : Char) : Bool
    char.ascii_alphanumeric? || char == '_'
  end

  # C++14 digit separators (`1'000'000`, `0x1'F`) are not char literals. Every
  # `'` opening one made the scanner run to EOF, so a handler containing one
  # yielded zero callees — parity-dependent, so it failed silently.
  private def digit_separator?(source : String, index : Int32) : Bool
    return false if index <= 0
    return false unless source.byte_at(index - 1).unsafe_chr.ascii_alphanumeric?
    return false if index + 1 >= source.bytesize
    return false unless source.byte_at(index + 1).unsafe_chr.ascii_alphanumeric?

    # Walk back to the start of the token: a separator only ever appears inside
    # a numeric literal, so the token must begin with a digit. This keeps the
    # `L'a'` / `u8'x'` / `U'x'` encoding prefixes reading as char literals.
    start = index - 1
    while start > 0
      char = source.byte_at(start - 1).unsafe_chr
      break unless char.ascii_alphanumeric? || char == '_' || char == '\'' || char == '.'
      start -= 1
    end

    source.byte_at(start).unsafe_chr.ascii_number?
  end

  private def skip_char_literal(source : String, index : Int32, limit : Int32) : Int32
    return index if digit_separator?(source, index)

    i = index + 1
    escaping = false

    while i < limit
      char = source.byte_at(i).unsafe_chr
      if escaping
        escaping = false
      elsif char == '\\'
        escaping = true
      elsif char == '\''
        return i
      end
      i += 1
    end

    limit - 1
  end

  private def skip_line_comment(source : String, index : Int32, limit : Int32) : Int32
    i = index
    while i < limit && source.byte_at(i).unsafe_chr != '\n'
      i += 1
    end
    i
  end

  private def skip_block_comment(source : String, index : Int32, limit : Int32) : Int32
    i = index + 2
    while i < limit
      return i + 1 if source.byte_at(i).unsafe_chr == '*' &&
                      i + 1 < limit &&
                      source.byte_at(i + 1).unsafe_chr == '/'

      i += 1
    end

    limit - 1
  end
end
