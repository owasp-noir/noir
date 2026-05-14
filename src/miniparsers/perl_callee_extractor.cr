require "../models/endpoint"

module Noir::PerlCalleeExtractor
  extend self

  alias Entry = Tuple(String, String, Int32)
  alias SubBody = NamedTuple(body: String, path: String, start_line: Int32)

  RESERVED = Set{
    "and", "cmp", "continue", "do", "else", "elsif", "eq", "eval",
    "for", "foreach", "ge", "given", "gt", "if", "last", "le", "lt",
    "my", "ne", "next", "no", "not", "our", "package", "return", "state",
    "sub", "unless", "until", "use", "when", "while",
    "bless", "caller", "chomp", "chop", "close", "defined", "delete",
    "die", "each", "exists", "grep", "join", "keys", "length", "map",
    "open", "pop", "print", "push", "qw", "q", "qq", "qr", "ref",
    "scalar", "shift", "sort", "split", "sprintf", "undef", "unshift",
    "values", "wantarray", "warn",
  }

  STANDARD_MODULES = Set{
    "Carp", "Data::Dumper", "Encode", "File::Spec", "JSON", "List::Util",
    "Mojo::Base", "Mojolicious::Lite", "strict", "warnings",
  }

  METHOD_CALL_REGEX    = /(\$?[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*)\s*->\s*([A-Za-z_][A-Za-z0-9_]*)(?![A-Za-z0-9_])\s*(?:\(|(?=\s*(?:[A-Za-z_$'"]|\{|\[|;|,|\)|\}|$)))/
  QUALIFIED_CALL_REGEX = /(?<![A-Za-z0-9_:])([A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)+)\s*(?:\(|(?=\s+(?:[A-Za-z_$'"]|\{|\[)))/
  BARE_CALL_REGEX      = /(?<![A-Za-z0-9_:>$])([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(|(?=\s+(?:[A-Za-z_$'"]|\{|\[)))/

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry
    stripped = strip_nested_sub_bodies(strip_non_code(body))

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

  def controller_action_callees(source : String, file_path : String) : Hash(String, Array(Entry))
    package = package_name(source)
    return {} of String => Array(Entry) unless package
    return {} of String => Array(Entry) unless package.includes?("::Controller::")

    controller = package.split("::Controller::", 2)[1]?
    return {} of String => Array(Entry) unless controller

    bodies = named_sub_bodies(source, file_path)
    actions = {} of String => Array(Entry)
    controller_keys(controller).each do |controller_key|
      bodies.each do |action, body|
        key = "#{controller_key}##{action}"
        actions[key] = callees_for_body(body[:body], body[:path], body[:start_line])
      end
    end

    actions
  end

  def named_sub_bodies(source : String, file_path : String) : Hash(String, SubBody)
    bodies = {} of String => SubBody
    stripped = strip_non_code(source)

    stripped.scan(/\bsub\s+([A-Za-z_][A-Za-z0-9_]*)\b/) do |match|
      sub_index = match.begin(0) || 0
      next unless sub_keyword_at?(source, sub_index)
      next unless body = extract_sub_at(source, sub_index)

      body_text, start_line = body
      bodies[match[1]] ||= {body: body_text, path: file_path, start_line: start_line}
    end

    bodies
  end

  def extract_sub_after(source : String,
                        start_index : Int32,
                        search_limit : Int32 = source.size,
                        body_limit : Int32 = source.size) : Tuple(String, Int32)?
    sub_index = find_keyword(source, "sub", start_index, search_limit)
    return unless sub_index

    extract_sub_at(source, sub_index, body_limit)
  end

  def extract_sub_at(source : String,
                     sub_index : Int32,
                     limit : Int32 = source.size) : Tuple(String, Int32)?
    return unless sub_keyword_at?(source, sub_index)

    open_brace = find_char(source, '{', sub_index, limit)
    return unless open_brace
    close_brace = find_matching_delimiter(source, open_brace, '{', '}', limit)
    return unless close_brace

    {source[(open_brace + 1)...close_brace], line_number_for(source, open_brace + 1)}
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
      elsif quote_like_start?(source, index)
        index = skip_quote_like(source, index, limit)
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
      elsif quote_like_start?(source, index)
        finish = skip_quote_like(source, index, source.size)
        append_string_placeholder(stripped, source, index, finish)
        index = finish
        next
      elsif char == '"' || char == '\''
        finish = skip_short_string(source, index, source.size)
        append_string_placeholder(stripped, source, index, finish)
        index = finish
        next
      end

      stripped << char
      index += 1
    end

    stripped.to_s
  end

  def line_number_for(source : String, index : Int32) : Int32
    return 1 if index <= 0

    limit = index > source.size ? source.size : index
    source[0...limit].count('\n') + 1
  end

  private def scan_line(line : String, file_path : String, line_number : Int32, entries : Array(Entry))
    candidates = [] of Tuple(Int32, String)

    line.scan(METHOD_CALL_REGEX) do |match|
      candidates << {match.begin(0) || 0, "#{normalize_receiver(match[1])}.#{match[2]}"}
    end
    scan_candidates(line, QUALIFIED_CALL_REGEX, candidates)
    scan_candidates(line, BARE_CALL_REGEX, candidates)

    candidates.sort_by! { |position, _| position }
    candidates.each do |position, name|
      next if skip_callee?(name)
      next if declaration_name?(line, position)

      entries << {name, file_path, line_number}
    end
  end

  private def scan_candidates(line : String, regex : Regex, candidates : Array(Tuple(Int32, String)))
    line.scan(regex) do |match|
      candidates << {match.begin(1) || 0, match[1]}
    end
  end

  private def normalize_receiver(name : String) : String
    normalized = name.starts_with?("$") ? name[1..] : name
    normalized.gsub("::", ".")
  end

  private def skip_callee?(name : String) : Bool
    return true if name.empty?

    base = name.split('.').last
    return true if RESERVED.includes?(base)
    return true if STANDARD_MODULES.includes?(name)

    false
  end

  private def declaration_name?(line : String, position : Int32) : Bool
    prefix = line[0...position]
    !!prefix.match(/\bsub\s+$/)
  end

  private def strip_nested_sub_bodies(source : String) : String
    stripped = String::Builder.new
    index = 0

    while index < source.size
      if sub_keyword_at?(source, index)
        finish = find_matching_sub_end(source, index) || index + "sub".size
        append_blanks(stripped, source, index, finish)
        index = finish
        next
      end

      stripped << source[index]
      index += 1
    end

    stripped.to_s
  end

  private def find_matching_sub_end(source : String, sub_index : Int32) : Int32?
    open_brace = find_char(source, '{', sub_index, source.size)
    return unless open_brace
    close_brace = find_matching_delimiter(source, open_brace, '{', '}', source.size)
    return unless close_brace
    close_brace + 1
  end

  private def package_name(source : String) : String?
    stripped = strip_non_code(source)
    if match = stripped.match(/^\s*package\s+([A-Za-z_][A-Za-z0-9_:]*)\s*;/m)
      match[1]
    end
  end

  private def controller_keys(controller : String) : Array(String)
    keys = Set(String).new
    segments = controller.split("::")
    keys << segments.map(&.downcase).join("/")
    keys << segments.map { |segment| underscore(segment) }.join("/")
    keys.to_a
  end

  private def underscore(name : String) : String
    name.gsub(/([a-z0-9])([A-Z])/, "\\1_\\2").downcase
  end

  private def find_keyword(source : String, keyword : String, start_index : Int32, limit : Int32) : Int32?
    index = start_index

    while index < limit && index < source.size
      if comment_start?(source, index)
        index = skip_comment(source, index, limit)
        next
      elsif quote_like_start?(source, index)
        index = skip_quote_like(source, index, limit)
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
      elsif quote_like_start?(source, index)
        index = skip_quote_like(source, index, limit)
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

  private def sub_keyword_at?(source : String, index : Int32) : Bool
    return false unless source[index, "sub".size]? == "sub"
    before = index > 0 ? source[index - 1] : '\0'
    after_index = index + "sub".size
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
    source[index] == '#'
  end

  private def skip_comment(source : String, index : Int32, limit : Int32) : Int32
    cursor = index
    while cursor < limit && cursor < source.size && source[cursor] != '\n'
      cursor += 1
    end
    cursor
  end

  private def quote_like_start?(source : String, index : Int32) : Bool
    return false unless index < source.size
    return false unless source[index] == 'q'
    return false if index > 0 && identifier_part?(source[index - 1])

    cursor = index + 1
    if cursor < source.size && {'q', 'r', 'w', 'x'}.includes?(source[cursor])
      cursor += 1
    elsif cursor < source.size && identifier_part?(source[cursor])
      return false
    end

    while cursor < source.size && source[cursor].whitespace?
      cursor += 1
    end
    return false if cursor >= source.size

    !!quote_close_char(source[cursor])
  end

  private def skip_quote_like(source : String, index : Int32, limit : Int32) : Int32
    cursor = index + 1
    cursor += 1 if cursor < limit && cursor < source.size && {'q', 'r', 'w', 'x'}.includes?(source[cursor])
    while cursor < limit && cursor < source.size && source[cursor].whitespace?
      cursor += 1
    end
    return index + 1 if cursor >= limit || cursor >= source.size

    open_char = source[cursor]
    close_char = quote_close_char(open_char)
    return index + 1 unless close_char

    cursor += 1
    escaped = false
    while cursor < limit && cursor < source.size
      char = source[cursor]
      if escaped
        escaped = false
      elsif char == '\\'
        escaped = true
      elsif char == close_char
        return cursor + 1
      end
      cursor += 1
    end

    limit
  end

  private def quote_close_char(open_char : Char) : Char?
    case open_char
    when '('                      then ')'
    when '['                      then ']'
    when '{'                      then '}'
    when '<'                      then '>'
    when '"', '\'', '/', '|', '!' then open_char
    end
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

  private def append_string_placeholder(builder : String::Builder, source : String, start_index : Int32, finish_index : Int32)
    placeholder_written = false
    index = start_index
    while index < finish_index && index < source.size
      if source[index] == '\n'
        builder << '\n'
      elsif !placeholder_written
        builder << ' '
        placeholder_written = true
      else
        builder << ' '
      end
      index += 1
    end
  end

  private def dedup_entries(entries : Array(Entry)) : Array(Entry)
    seen = Set(Entry).new
    entries.select { |entry| seen.add?(entry) }
  end
end
