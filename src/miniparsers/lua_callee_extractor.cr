require "../models/endpoint"

module Noir::LuaCalleeExtractor
  extend self

  alias Entry = Tuple(String, String, Int32)
  alias FunctionBody = NamedTuple(body: String, path: String, start_line: Int32)

  RESERVED = Set{
    "and", "break", "do", "else", "elseif", "end", "false", "for",
    "function", "goto", "if", "in", "local", "nil", "not", "or",
    "repeat", "return", "then", "true", "until", "while",
    "assert", "collectgarbage", "dofile", "error", "getmetatable",
    "ipairs", "load", "loadfile", "next", "pairs", "pcall", "print",
    "rawequal", "rawget", "rawlen", "rawset", "require", "select",
    "setmetatable", "tonumber", "tostring", "type", "xpcall",
  }

  STANDARD_LIB_ROOTS = Set{
    "coroutine", "debug", "io", "math", "os", "package", "string",
    "table", "utf8",
  }

  RECEIVER_CALL_REGEX = /(?<![A-Za-z0-9_@])(@?[A-Za-z_][A-Za-z0-9_]*(?:(?:\s*[.:\\]\s*)[A-Za-z_][A-Za-z0-9_]*)+)\s*(?:\(|(?=\s+(?:["'{]|\[\[|@)))/
  SELF_CALL_REGEX     = /(?<![A-Za-z0-9_])(@[A-Za-z_][A-Za-z0-9_]*)\s*(?:\(|(?=\s+(?:["'{]|\[\[|[A-Za-z_@])))/
  BARE_CALL_REGEX     = /(?<![A-Za-z0-9_.:\\@])([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(|(?=\s*(?:["'{]|\[\[)))/
  COMMAND_CALL_REGEX  = /(?:^\s*|[=,;]\s*|\breturn\s+)([A-Za-z_][A-Za-z0-9_]*)\s+(?=["'{A-Za-z_@\[])/

  def function_bodies(source : String, file_path : String) : Hash(String, FunctionBody)
    bodies = {} of String => FunctionBody
    stripped = strip_non_code(source)

    stripped.scan(/\bfunction\s+([A-Za-z_][A-Za-z0-9_]*(?:(?:[:.])[A-Za-z_][A-Za-z0-9_]*)*)\s*\(/) do |match|
      function_index = match.begin(0) || 0
      next unless function_keyword_at?(source, function_index)

      if body = extract_function_at(source, function_index)
        name = match[1]
        add_function_body(bodies, name, body, file_path)
      end
    end

    stripped.scan(/(?:^|[\n,{])\s*(?:local\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\b/) do |match|
      function_index = (match.begin(0) || 0) + match[0].rindex!("function")
      next unless function_keyword_at?(source, function_index)

      if body = extract_function_at(source, function_index)
        add_function_body(bodies, match[1], body, file_path)
      end
    end

    bodies
  end

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry
    stripped = strip_nested_function_bodies(strip_non_code(body))

    stripped.each_line.with_index do |line, offset|
      scan_line(line, file_path, start_line + offset, entries)
    end

    dedup_entries(entries)
  end

  def attach_to(endpoint : Endpoint, callees : Array(Entry))
    callees.each do |name, path, line|
      endpoint.push_callee(Callee.new(name, path: path, line: line))
    end
  end

  def extract_function_after(source : String,
                             start_index : Int32,
                             search_limit : Int32 = source.size,
                             body_limit : Int32 = source.size) : Tuple(String, Int32)?
    function_index = find_keyword(source, "function", start_index, search_limit)
    return unless function_index

    extract_function_at(source, function_index, body_limit)
  end

  def extract_function_at(source : String,
                          function_index : Int32,
                          limit : Int32 = source.size) : Tuple(String, Int32)?
    return unless function_keyword_at?(source, function_index)

    body_start = function_body_start(source, function_index, limit)
    body_end = matching_function_end(source, function_index, limit)
    return unless body_end
    return if body_end < body_start

    {source[body_start...body_end], line_number_for(source, body_start)}
  end

  def extract_moonscript_block_after(source : String, arrow_end_index : Int32) : Tuple(String, Int32)?
    route_line_start = line_start_for(source, arrow_end_index)
    route_indent = indentation_at(source, route_line_start)
    route_line_end = line_end_for(source, arrow_end_index)
    tail = source[arrow_end_index...route_line_end].strip
    unless tail.empty?
      return {tail, line_number_for(source, arrow_end_index)}
    end

    body_lines = [] of String
    body_start_line = nil
    index = route_line_end < source.size ? route_line_end + 1 : source.size

    while index < source.size
      current_end = line_end_for(source, index)
      line = source[index...current_end]
      stripped = line.strip

      if stripped.empty?
        body_lines << line if body_start_line
        index = current_end < source.size ? current_end + 1 : source.size
        next
      end

      indent = indentation_at(source, index)
      break if indent <= route_indent

      body_start_line ||= line_number_for(source, index)
      body_lines << line
      index = current_end < source.size ? current_end + 1 : source.size
    end

    return unless body_start_line

    {body_lines.join("\n"), body_start_line}
  end

  def find_matching_delimiter(source : String, open_index : Int32, open_char : Char, close_char : Char,
                              limit : Int32 = source.size) : Int32?
    depth = 0
    index = open_index

    while index < limit && index < source.size
      char = source[index]
      if comment_start?(source, index)
        index = skip_comment(source, index, limit)
        next
      elsif long_bracket_start?(source, index)
        index = skip_long_bracket(source, index, limit)
        next
      elsif char == '"' || char == '\''
        index = skip_short_string(source, index, limit)
        next
      elsif char == open_char
        depth += 1
      elsif char == close_char
        depth -= 1
        return index if depth == 0
      end

      index += 1
    end

    nil
  end

  def line_number_for(source : String, index : Int32) : Int32
    return 1 if index <= 0

    limit = index > source.size ? source.size : index
    source[0...limit].count('\n') + 1
  end

  def strip_non_code(source : String) : String
    stripped = String::Builder.new
    index = 0

    while index < source.size
      char = source[index]
      if comment_start?(source, index)
        finish = skip_comment(source, index, source.size)
        append_blanks(stripped, source, index, finish)
        index = finish
        next
      elsif long_bracket_start?(source, index)
        finish = skip_long_bracket(source, index, source.size)
        append_string_placeholder(stripped, source, index, finish, "[[]]")
        index = finish
        next
      elsif char == '"' || char == '\''
        finish = skip_short_string(source, index, source.size)
        append_string_placeholder(stripped, source, index, finish, "#{char}#{char}")
        index = finish
        next
      end

      stripped << char
      index += 1
    end

    stripped.to_s
  end

  private def add_function_body(bodies : Hash(String, FunctionBody),
                                name : String,
                                body : Tuple(String, Int32),
                                file_path : String)
    body_text, start_line = body
    body_info = {body: body_text, path: file_path, start_line: start_line}
    bodies[name] ||= body_info
    short_name = name.split(/[.:]/).last
    bodies[short_name] ||= body_info
  end

  private def scan_line(line : String, file_path : String, line_number : Int32, entries : Array(Entry))
    candidates = [] of Tuple(Int32, String)

    scan_candidates(line, RECEIVER_CALL_REGEX, candidates)
    scan_candidates(line, SELF_CALL_REGEX, candidates)
    scan_candidates(line, BARE_CALL_REGEX, candidates)
    scan_candidates(line, COMMAND_CALL_REGEX, candidates)

    candidates.sort_by! { |position, _| position }
    candidates.each do |position, name|
      next if skip_callee?(name)
      next if declaration_name?(line, position)

      entries << {normalize_name(name), file_path, line_number}
    end
  end

  private def scan_candidates(line : String, regex : Regex, candidates : Array(Tuple(Int32, String)))
    line.scan(regex) do |match|
      candidates << {match.begin(1) || 0, match[1]}
    end
  end

  private def normalize_name(name : String) : String
    normalized = name.gsub(/\s+/, "").gsub('\\', '.').gsub(':', '.')
    normalized = "self.#{normalized[1..]}" if normalized.starts_with?("@")
    normalized
  end

  private def skip_callee?(name : String) : Bool
    return true if name.empty?

    normalized = normalize_name(name)
    parts = normalized.split('.')
    return STANDARD_LIB_ROOTS.includes?(parts.first) if parts.size > 1

    RESERVED.includes?(normalized)
  end

  private def declaration_name?(line : String, position : Int32) : Bool
    prefix = line[0...position]
    !!prefix.match(/\bfunction\s+$/)
  end

  private def strip_nested_function_bodies(source : String) : String
    stripped = String::Builder.new
    index = 0

    while index < source.size
      if function_keyword_at?(source, index)
        finish = if function_end = matching_function_end(source, index, source.size)
                   function_end + "end".size
                 else
                   index + "function".size
                 end
        append_blanks(stripped, source, index, finish)
        index = finish
        next
      end

      stripped << source[index]
      index += 1
    end

    stripped.to_s
  end

  private def function_body_start(source : String, function_index : Int32, limit : Int32) : Int32
    paren_index = find_char(source, '(', function_index, limit)
    return function_index + "function".size unless paren_index

    close_index = find_matching_delimiter(source, paren_index, '(', ')', limit)
    return close_index + 1 if close_index

    function_index + "function".size
  end

  private def matching_function_end(source : String, function_index : Int32, limit : Int32) : Int32?
    depth = 0
    pending_do = 0
    index = function_index

    while index < limit && index < source.size
      if comment_start?(source, index)
        index = skip_comment(source, index, limit)
        next
      elsif long_bracket_start?(source, index)
        index = skip_long_bracket(source, index, limit)
        next
      elsif source[index] == '"' || source[index] == '\''
        index = skip_short_string(source, index, limit)
        next
      elsif identifier_start?(source[index])
        token_start = index
        token, index = read_identifier(source, index, limit)
        case token
        when "function", "if", "repeat"
          depth += 1
        when "for", "while"
          depth += 1
          pending_do += 1
        when "do"
          if pending_do > 0
            pending_do -= 1
          else
            depth += 1
          end
        when "end"
          depth -= 1
          return token_start if depth == 0
        when "until"
          depth -= 1 if depth > 1
        end
        next
      end

      index += 1
    end

    nil
  end

  private def find_keyword(source : String, keyword : String, start_index : Int32, limit : Int32) : Int32?
    index = start_index

    while index < limit && index < source.size
      if comment_start?(source, index)
        index = skip_comment(source, index, limit)
        next
      elsif long_bracket_start?(source, index)
        index = skip_long_bracket(source, index, limit)
        next
      elsif source[index] == '"' || source[index] == '\''
        index = skip_short_string(source, index, limit)
        next
      elsif identifier_start?(source[index])
        token_start = index
        token, index = read_identifier(source, index, limit)
        return token_start if token == keyword
        next
      end

      index += 1
    end

    nil
  end

  private def find_char(source : String, target : Char, start_index : Int32, limit : Int32) : Int32?
    index = start_index

    while index < limit && index < source.size
      if comment_start?(source, index)
        index = skip_comment(source, index, limit)
        next
      elsif long_bracket_start?(source, index)
        index = skip_long_bracket(source, index, limit)
        next
      elsif source[index] == '"' || source[index] == '\''
        index = skip_short_string(source, index, limit)
        next
      end

      return index if source[index] == target

      index += 1
    end

    nil
  end

  private def function_keyword_at?(source : String, index : Int32) : Bool
    return false unless source[index, "function".size]? == "function"
    before = index > 0 ? source[index - 1] : '\0'
    after_index = index + "function".size
    after = after_index < source.size ? source[after_index] : '\0'
    !identifier_part?(before) && !identifier_part?(after)
  end

  private def read_identifier(source : String, index : Int32, limit : Int32) : Tuple(String, Int32)
    cursor = index
    while cursor < limit && cursor < source.size && identifier_part?(source[cursor])
      cursor += 1
    end

    {source[index...cursor], cursor}
  end

  private def identifier_start?(char : Char) : Bool
    char.ascii_letter? || char == '_'
  end

  private def identifier_part?(char : Char) : Bool
    char.ascii_alphanumeric? || char == '_'
  end

  private def comment_start?(source : String, index : Int32) : Bool
    index + 1 < source.size && source[index] == '-' && source[index + 1] == '-'
  end

  private def skip_comment(source : String, index : Int32, limit : Int32) : Int32
    if index + 2 < limit && long_bracket_start?(source, index + 2)
      skip_long_bracket(source, index + 2, limit)
    else
      cursor = index
      while cursor < limit && cursor < source.size && source[cursor] != '\n'
        cursor += 1
      end
      cursor
    end
  end

  private def long_bracket_start?(source : String, index : Int32) : Bool
    !!long_bracket_equals(source, index)
  end

  private def long_bracket_equals(source : String, index : Int32) : Int32?
    return unless index < source.size && source[index] == '['

    cursor = index + 1
    equals = 0
    while cursor < source.size && source[cursor] == '='
      equals += 1
      cursor += 1
    end

    return equals if cursor < source.size && source[cursor] == '['
    nil
  end

  private def skip_long_bracket(source : String, index : Int32, limit : Int32) : Int32
    equals = long_bracket_equals(source, index)
    return index + 1 unless equals

    cursor = index + equals + 2
    while cursor < limit && cursor < source.size
      if source[cursor] == ']'
        close_cursor = cursor + 1
        seen_equals = 0
        while close_cursor < source.size && source[close_cursor] == '='
          seen_equals += 1
          close_cursor += 1
        end
        return close_cursor + 1 if seen_equals == equals && close_cursor < source.size && source[close_cursor] == ']'
      end
      cursor += 1
    end

    limit
  end

  private def skip_short_string(source : String, index : Int32, limit : Int32) : Int32
    quote = source[index]
    cursor = index + 1
    escaped = false

    while cursor < limit && cursor < source.size
      char = source[cursor]
      if escaped
        escaped = false
      elsif char == '\\'
        escaped = true
      elsif char == quote
        return cursor + 1
      end
      cursor += 1
    end

    limit
  end

  private def append_blanks(builder : String::Builder, source : String, start_index : Int32, finish_index : Int32)
    index = start_index
    while index < finish_index && index < source.size
      builder << (source[index] == '\n' ? '\n' : ' ')
      index += 1
    end
  end

  private def append_string_placeholder(builder : String::Builder, source : String,
                                        start_index : Int32, finish_index : Int32, placeholder : String)
    placeholder_index = 0
    index = start_index
    while index < finish_index && index < source.size
      if source[index] == '\n'
        builder << '\n'
      elsif placeholder_index < placeholder.size
        builder << placeholder[placeholder_index]
        placeholder_index += 1
      else
        builder << ' '
      end
      index += 1
    end
  end

  private def line_start_for(source : String, index : Int32) : Int32
    cursor = index
    while cursor > 0 && source[cursor - 1] != '\n'
      cursor -= 1
    end
    cursor
  end

  private def line_end_for(source : String, index : Int32) : Int32
    cursor = index
    while cursor < source.size && source[cursor] != '\n'
      cursor += 1
    end
    cursor
  end

  private def indentation_at(source : String, line_start : Int32) : Int32
    cursor = line_start
    indent = 0
    while cursor < source.size
      case source[cursor]
      when ' '
        indent += 1
      when '\t'
        indent += 2
      else
        break
      end
      cursor += 1
    end
    indent
  end

  private def dedup_entries(entries : Array(Entry)) : Array(Entry)
    seen = Set(Entry).new
    entries.select { |entry| seen.add?(entry) }
  end
end
