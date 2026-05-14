require "../models/endpoint"

module Noir::CppCalleeExtractor
  extend self

  alias Entry = Tuple(String, String, Int32)

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

    body.each_line.with_index do |line, index|
      stripped, in_block_comment = strip_non_code_with_state(line, in_block_comment)
      scan_line(stripped, file_path, start_line + index, entries)
    end

    dedup_entries(entries)
  end

  def attach_to(endpoint : Endpoint, callees : Array(Entry))
    callees.each do |name, path, line|
      endpoint.push_callee(Callee.new(name, path: path, line: line))
    end
  end

  def extract_block_after(source : String, start_index : Int32, limit : Int32 = source.bytesize) : Tuple(String, Int32)?
    open_index = find_next_code_char(source, '{', start_index, limit)
    return unless open_index

    close_index = find_matching_delimiter(source, open_index, '{', '}', limit)
    return unless close_index

    {source[(open_index + 1)...close_index], line_number_for(source, open_index)}
  end

  def extract_lambda_block_after(source : String, start_index : Int32, limit : Int32 = source.bytesize) : Tuple(String, Int32)?
    open_index = find_next_code_char(source, '{', start_index, limit)
    return unless open_index
    return if find_next_code_char(source, ';', start_index, open_index)
    return unless source[start_index...open_index].includes?('[')

    close_index = find_matching_delimiter(source, open_index, '{', '}', limit)
    return unless close_index

    {source[(open_index + 1)...close_index], line_number_for(source, open_index)}
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

  private def scan_line(line : String, file_path : String, line_number : Int32, entries : Array(Entry))
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

  private def strip_non_code_with_state(line : String, in_block_comment : Bool) : Tuple(String, Bool)
    chars = line.chars
    in_string = false
    in_char = false
    escaped = false
    index = 0
    stripped = String::Builder.new

    while index < chars.size
      char = chars[index]

      if in_block_comment
        if char == '*' && chars[index + 1]? == '/'
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
      elsif char == '"'
        in_string = true
      elsif char == '\''
        in_char = true
      elsif char == '/' && chars[index + 1]? == '/'
        break
      elsif char == '/' && chars[index + 1]? == '*'
        in_block_comment = true
        index += 1
      else
        stripped << char
      end

      index += 1
    end

    {stripped.to_s, in_block_comment}
  end

  private def skip_string(source : String, index : Int32, limit : Int32) : Int32
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

  private def skip_char_literal(source : String, index : Int32, limit : Int32) : Int32
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

  private def dedup_entries(entries : Array(Entry)) : Array(Entry)
    seen = Set(Entry).new
    entries.select { |entry| seen.add?(entry) }
  end
end
