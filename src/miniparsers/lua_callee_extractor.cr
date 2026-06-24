require "../models/endpoint"
require "./callee_extractor_base"

module Noir::LuaCalleeExtractor
  extend self
  include Noir::CalleeExtractorBase

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

  # MoonScript-only keywords. These are NOT Lua keywords — `class`,
  # `import`, `from`, `with`, `switch`, … are all legal (and common,
  # e.g. middleclass's `class("Foo")`) Lua function names — so they are
  # filtered ONLY when the source file is `.moon`, where `import X from`,
  # `class … extends …`, and `switch`/`when` are statement keywords that
  # would otherwise surface as phantom callees.
  MOONSCRIPT_RESERVED = Set{
    "import", "export", "from", "class", "extends", "with", "using",
    "switch", "when", "unless", "continue",
  }

  STANDARD_LIB_ROOTS = Set{
    "coroutine", "debug", "io", "math", "os", "package", "string",
    "table", "utf8",
  }

  # A receiver chain is `a.b`, `a:b` (Lua method call), or `a\b`
  # (MoonScript method call). The `:` separator is kept space-free so a
  # MoonScript table entry (`success: Flow(...)`, where `:` is a hash
  # separator, not method access) is not glued onto the following call —
  # Lua's `obj:method` never carries surrounding whitespace, whereas a
  # MoonScript key always does. `.` and `\` keep optional whitespace.
  RECEIVER_CALL_REGEX = /(?<![A-Za-z0-9_@])(@?[A-Za-z_][A-Za-z0-9_]*(?:(?:\s*[.\\]\s*|:)[A-Za-z_][A-Za-z0-9_]*)+)\s*(?:\(|(?=\s+(?:["'{]|\[\[|@)))/
  SELF_CALL_REGEX     = /(?<![A-Za-z0-9_])(@[A-Za-z_][A-Za-z0-9_]*)\s*(?:\(|(?=\s+(?:["'{]|\[\[|[A-Za-z_@])))/
  BARE_CALL_REGEX     = /(?<![A-Za-z0-9_.:\\@])([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(|(?=\s*(?:["'{]|\[\[)))/
  COMMAND_CALL_REGEX  = /(?:^\s*|[=,;]\s*|\breturn\s+)([A-Za-z_][A-Za-z0-9_]*)\s+(?=["'{A-Za-z_@\[])/

  # The structural scanners below address characters by integer index. On a
  # String that is not single-byte-optimizable (any non-ASCII character —
  # even one in a comment), `String#[](Int)` is O(n), so the per-character
  # loops degrade to O(n²) and hang the scan on a large file. They run over an
  # `Array(Char)` (O(1) indexing) while preserving exact character semantics;
  # every structural token matched is ASCII and substrings are rebuilt from
  # the real characters. Public String entry points are kept as thin overloads.

  def function_bodies(source : String, file_path : String) : Hash(String, FunctionBody)
    bodies = {} of String => FunctionBody
    chars = source.chars
    stripped = strip_non_code(chars)

    stripped.scan(/\bfunction\s+([A-Za-z_][A-Za-z0-9_]*(?:(?:[:.])[A-Za-z_][A-Za-z0-9_]*)*)\s*\(/) do |match|
      function_index = match.begin(0) || 0
      next unless function_keyword_at?(chars, function_index)

      if body = extract_function_at(chars, function_index)
        name = match[1]
        add_function_body(bodies, name, body, file_path)
      end
    end

    stripped.scan(/(?:^|[\n,{])\s*(?:local\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\b/) do |match|
      function_index = (match.begin(0) || 0) + match[0].rindex!("function")
      next unless function_keyword_at?(chars, function_index)

      if body = extract_function_at(chars, function_index)
        add_function_body(bodies, match[1], body, file_path)
      end
    end

    bodies
  end

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry
    stripped = strip_nested_function_bodies(strip_non_code(body).chars)

    stripped.each_line.with_index do |line, offset|
      scan_line(line, file_path, start_line + offset, entries)
    end

    dedup_entries(entries)
  end

  def extract_function_after(source : String,
                             start_index : Int32,
                             search_limit : Int32 = source.size,
                             body_limit : Int32 = source.size) : Tuple(String, Int32)?
    chars = source.chars
    function_index = find_keyword(chars, "function", start_index, search_limit)
    return unless function_index

    extract_function_at(chars, function_index, body_limit)
  end

  # Public String overload kept for callers outside this module.
  def extract_function_at(source : String,
                          function_index : Int32,
                          limit : Int32 = source.size) : Tuple(String, Int32)?
    extract_function_at(source.chars, function_index, limit)
  end

  def extract_function_at(chars : Array(Char),
                          function_index : Int32,
                          limit : Int32 = chars.size) : Tuple(String, Int32)?
    return unless function_keyword_at?(chars, function_index)

    body_start = function_body_start(chars, function_index, limit)
    body_end = matching_function_end(chars, function_index, limit)
    return unless body_end
    return if body_end < body_start

    {chars[body_start...body_end].join, line_number_for(chars, body_start)}
  end

  # Public String overload kept for callers outside this module.
  def extract_moonscript_block_after(source : String, arrow_end_index : Int32) : Tuple(String, Int32)?
    extract_moonscript_block_after(source.chars, arrow_end_index)
  end

  def extract_moonscript_block_after(chars : Array(Char), arrow_end_index : Int32) : Tuple(String, Int32)?
    route_line_start = line_start_for(chars, arrow_end_index)
    route_indent = indentation_at(chars, route_line_start)
    route_line_end = line_end_for(chars, arrow_end_index)
    tail = chars[arrow_end_index...route_line_end].join.strip
    unless tail.empty?
      return {tail, line_number_for(chars, arrow_end_index)}
    end

    body_lines = [] of String
    body_start_line = nil
    index = route_line_end < chars.size ? route_line_end + 1 : chars.size

    while index < chars.size
      current_end = line_end_for(chars, index)
      line = chars[index...current_end].join
      stripped = line.strip

      if stripped.empty?
        body_lines << line if body_start_line
        index = current_end < chars.size ? current_end + 1 : chars.size
        next
      end

      indent = indentation_at(chars, index)
      break if indent <= route_indent

      body_start_line ||= line_number_for(chars, index)
      body_lines << line
      index = current_end < chars.size ? current_end + 1 : chars.size
    end

    return unless body_start_line

    {body_lines.join("\n"), body_start_line}
  end

  # Extract a MoonScript class-action value: everything from `value_start`
  # (just past a route header's `:`) through the end of the indentation
  # block the header introduces. Unlike `extract_moonscript_block_after`,
  # which assumes an inline arrow and stops at the first body line, this
  # keeps the header line's trailing content (`respond_to {`, a wrapper
  # call, an inline arrow) together with every more-indented line that
  # follows, so `respond_to` blocks and wrapped handlers are captured
  # whole. `start_line` is the header line, matching the offsets callers
  # already expect for inline arrows.
  #
  # Public String overload kept for callers outside this module.
  def moonscript_value_region(source : String, value_start : Int32) : Tuple(String, Int32)?
    moonscript_value_region(source.chars, value_start)
  end

  def moonscript_value_region(chars : Array(Char), value_start : Int32) : Tuple(String, Int32)?
    return if value_start >= chars.size

    header_line_start = line_start_for(chars, value_start)
    header_indent = indentation_at(chars, header_line_start)
    region_end = line_end_for(chars, value_start)
    index = region_end < chars.size ? region_end + 1 : chars.size

    while index < chars.size
      current_end = line_end_for(chars, index)
      line = chars[index...current_end].join

      if line.strip.empty?
        region_end = current_end
        index = current_end < chars.size ? current_end + 1 : chars.size
        next
      end

      break if indentation_at(chars, index) <= header_indent

      region_end = current_end
      index = current_end < chars.size ? current_end + 1 : chars.size
    end

    return if region_end <= value_start
    {chars[value_start...region_end].join, line_number_for(chars, value_start)}
  end

  # Public String overload kept for callers outside this module.
  def find_matching_delimiter(source : String, open_index : Int32, open_char : Char, close_char : Char,
                              limit : Int32 = source.size) : Int32?
    find_matching_delimiter(source.chars, open_index, open_char, close_char, limit)
  end

  def find_matching_delimiter(chars : Array(Char), open_index : Int32, open_char : Char, close_char : Char,
                              limit : Int32 = chars.size) : Int32?
    depth = 0
    index = open_index

    while index < limit && index < chars.size
      char = chars[index]
      if comment_start?(chars, index)
        index = skip_comment(chars, index, limit)
        next
      elsif long_bracket_start?(chars, index)
        index = skip_long_bracket(chars, index, limit)
        next
      elsif char == '"' || char == '\''
        index = skip_short_string(chars, index, limit)
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

  # Public String overload kept for callers outside this module.
  def line_number_for(source : String, index : Int32) : Int32
    return 1 if index <= 0

    limit = index > source.size ? source.size : index
    source[0...limit].count('\n') + 1
  end

  def line_number_for(chars : Array(Char), index : Int32) : Int32
    return 1 if index <= 0

    limit = index > chars.size ? chars.size : index
    count = 1
    i = 0
    while i < limit
      count += 1 if chars[i] == '\n'
      i += 1
    end
    count
  end

  # Public String overload kept for callers outside this module.
  def strip_non_code(source : String) : String
    strip_non_code(source.chars)
  end

  def strip_non_code(chars : Array(Char)) : String
    stripped = String::Builder.new
    index = 0

    while index < chars.size
      char = chars[index]
      if comment_start?(chars, index)
        finish = skip_comment(chars, index, chars.size)
        append_blanks(stripped, chars, index, finish)
        index = finish
        next
      elsif long_bracket_start?(chars, index)
        finish = skip_long_bracket(chars, index, chars.size)
        append_string_placeholder(stripped, chars, index, finish, "[[]]")
        index = finish
        next
      elsif char == '"' || char == '\''
        finish = skip_short_string(chars, index, chars.size)
        append_string_placeholder(stripped, chars, index, finish, "#{char}#{char}")
        index = finish
        next
      end

      stripped << char
      index += 1
    end

    stripped.to_s
  end

  # Blank out comments and long-bracket (`[[ ]]`/`[=[ ]=]`) string bodies but
  # PRESERVE short-string contents verbatim. Route analyzers need the path
  # literals (`app:get("/login", …)`) intact while still suppressing `--`
  # comments and here-strings that would otherwise leak phantom routes.
  # Newlines are kept so line-anchored scans and line numbering stay aligned.
  def strip_comments(source : String) : String
    strip_comments(source.chars)
  end

  def strip_comments(chars : Array(Char)) : String
    stripped = String::Builder.new
    index = 0

    while index < chars.size
      char = chars[index]
      if comment_start?(chars, index)
        finish = skip_comment(chars, index, chars.size)
        append_blanks(stripped, chars, index, finish)
        index = finish
        next
      elsif long_bracket_start?(chars, index)
        finish = skip_long_bracket(chars, index, chars.size)
        append_blanks(stripped, chars, index, finish)
        index = finish
        next
      elsif char == '"' || char == '\''
        finish = skip_short_string(chars, index, chars.size)
        cursor = index
        while cursor < finish && cursor < chars.size
          stripped << chars[cursor]
          cursor += 1
        end
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

    moonscript = file_path.ends_with?(".moon")
    candidates.sort_by! { |position, _| position }
    candidates.each do |position, name|
      next if skip_callee?(name, moonscript)
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

  private def skip_callee?(name : String, moonscript : Bool = false) : Bool
    return true if name.empty?

    normalized = normalize_name(name)
    parts = normalized.split('.')
    return STANDARD_LIB_ROOTS.includes?(parts.first) if parts.size > 1

    RESERVED.includes?(normalized) || (moonscript && MOONSCRIPT_RESERVED.includes?(normalized))
  end

  private def declaration_name?(line : String, position : Int32) : Bool
    prefix = line[0...position]
    !!prefix.match(/\bfunction\s+$/)
  end

  private def strip_nested_function_bodies(chars : Array(Char)) : String
    stripped = String::Builder.new
    index = 0

    while index < chars.size
      if function_keyword_at?(chars, index)
        finish = if function_end = matching_function_end(chars, index, chars.size)
                   function_end + "end".size
                 else
                   index + "function".size
                 end
        append_blanks(stripped, chars, index, finish)
        index = finish
        next
      end

      stripped << chars[index]
      index += 1
    end

    stripped.to_s
  end

  private def function_body_start(chars : Array(Char), function_index : Int32, limit : Int32) : Int32
    paren_index = find_char(chars, '(', function_index, limit)
    return function_index + "function".size unless paren_index

    close_index = find_matching_delimiter(chars, paren_index, '(', ')', limit)
    return close_index + 1 if close_index

    function_index + "function".size
  end

  private def matching_function_end(chars : Array(Char), function_index : Int32, limit : Int32) : Int32?
    depth = 0
    pending_do = 0
    index = function_index

    while index < limit && index < chars.size
      if comment_start?(chars, index)
        index = skip_comment(chars, index, limit)
        next
      elsif long_bracket_start?(chars, index)
        index = skip_long_bracket(chars, index, limit)
        next
      elsif chars[index] == '"' || chars[index] == '\''
        index = skip_short_string(chars, index, limit)
        next
      elsif identifier_start?(chars[index])
        token_start = index
        token, index = read_identifier(chars, index, limit)
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

  private def find_keyword(chars : Array(Char), keyword : String, start_index : Int32, limit : Int32) : Int32?
    index = start_index

    while index < limit && index < chars.size
      if comment_start?(chars, index)
        index = skip_comment(chars, index, limit)
        next
      elsif long_bracket_start?(chars, index)
        index = skip_long_bracket(chars, index, limit)
        next
      elsif chars[index] == '"' || chars[index] == '\''
        index = skip_short_string(chars, index, limit)
        next
      elsif identifier_start?(chars[index])
        token_start = index
        token, index = read_identifier(chars, index, limit)
        return token_start if token == keyword
        next
      end

      index += 1
    end

    nil
  end

  private def find_char(chars : Array(Char), target : Char, start_index : Int32, limit : Int32) : Int32?
    index = start_index

    while index < limit && index < chars.size
      if comment_start?(chars, index)
        index = skip_comment(chars, index, limit)
        next
      elsif long_bracket_start?(chars, index)
        index = skip_long_bracket(chars, index, limit)
        next
      elsif chars[index] == '"' || chars[index] == '\''
        index = skip_short_string(chars, index, limit)
        next
      end

      return index if chars[index] == target

      index += 1
    end

    nil
  end

  private def function_keyword_at?(chars : Array(Char), index : Int32) : Bool
    return false unless chars[index, "function".size]?.try(&.join) == "function"
    before = index > 0 ? chars[index - 1] : '\0'
    after_index = index + "function".size
    after = after_index < chars.size ? chars[after_index] : '\0'
    !identifier_part?(before) && !identifier_part?(after)
  end

  private def read_identifier(chars : Array(Char), index : Int32, limit : Int32) : Tuple(String, Int32)
    cursor = index
    while cursor < limit && cursor < chars.size && identifier_part?(chars[cursor])
      cursor += 1
    end

    {chars[index...cursor].join, cursor}
  end

  private def identifier_start?(char : Char) : Bool
    char.ascii_letter? || char == '_'
  end

  private def identifier_part?(char : Char) : Bool
    char.ascii_alphanumeric? || char == '_'
  end

  private def comment_start?(chars : Array(Char), index : Int32) : Bool
    index + 1 < chars.size && chars[index] == '-' && chars[index + 1] == '-'
  end

  private def skip_comment(chars : Array(Char), index : Int32, limit : Int32) : Int32
    if index + 2 < limit && long_bracket_start?(chars, index + 2)
      skip_long_bracket(chars, index + 2, limit)
    else
      cursor = index
      while cursor < limit && cursor < chars.size && chars[cursor] != '\n'
        cursor += 1
      end
      cursor
    end
  end

  private def long_bracket_start?(chars : Array(Char), index : Int32) : Bool
    !!long_bracket_equals(chars, index)
  end

  private def long_bracket_equals(chars : Array(Char), index : Int32) : Int32?
    return unless index < chars.size && chars[index] == '['

    cursor = index + 1
    equals = 0
    while cursor < chars.size && chars[cursor] == '='
      equals += 1
      cursor += 1
    end

    return equals if cursor < chars.size && chars[cursor] == '['
    nil
  end

  private def skip_long_bracket(chars : Array(Char), index : Int32, limit : Int32) : Int32
    equals = long_bracket_equals(chars, index)
    return index + 1 unless equals

    cursor = index + equals + 2
    while cursor < limit && cursor < chars.size
      if chars[cursor] == ']'
        close_cursor = cursor + 1
        seen_equals = 0
        while close_cursor < chars.size && chars[close_cursor] == '='
          seen_equals += 1
          close_cursor += 1
        end
        return close_cursor + 1 if seen_equals == equals && close_cursor < chars.size && chars[close_cursor] == ']'
      end
      cursor += 1
    end

    limit
  end

  private def skip_short_string(chars : Array(Char), index : Int32, limit : Int32) : Int32
    quote = chars[index]
    cursor = index + 1
    escaped = false

    while cursor < limit && cursor < chars.size
      char = chars[cursor]
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

  private def append_blanks(builder : String::Builder, chars : Array(Char), start_index : Int32, finish_index : Int32)
    index = start_index
    while index < finish_index && index < chars.size
      builder << (chars[index] == '\n' ? '\n' : ' ')
      index += 1
    end
  end

  private def append_string_placeholder(builder : String::Builder, chars : Array(Char),
                                        start_index : Int32, finish_index : Int32, placeholder : String)
    placeholder_index = 0
    index = start_index
    while index < finish_index && index < chars.size
      if chars[index] == '\n'
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

  private def line_start_for(chars : Array(Char), index : Int32) : Int32
    cursor = index
    while cursor > 0 && chars[cursor - 1] != '\n'
      cursor -= 1
    end
    cursor
  end

  private def line_end_for(chars : Array(Char), index : Int32) : Int32
    cursor = index
    while cursor < chars.size && chars[cursor] != '\n'
      cursor += 1
    end
    cursor
  end

  private def indentation_at(chars : Array(Char), line_start : Int32) : Int32
    cursor = line_start
    indent = 0
    while cursor < chars.size
      case chars[cursor]
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
end
