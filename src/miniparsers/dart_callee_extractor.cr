require "../models/endpoint"
require "./callee_extractor_base"

module Noir::DartCalleeExtractor
  extend self
  include Noir::CalleeExtractorBase

  alias BodyInfo = Tuple(String, Int32, Int32)
  alias StripState = NamedTuple(block_comment: Bool, triple_quote: Char)

  INITIAL_STATE = {
    block_comment: false,
    triple_quote:  '\0',
  }

  RESERVED = Set{
    "abstract", "as", "assert", "async", "await", "break", "case",
    "catch", "class", "const", "continue", "covariant", "default",
    "deferred", "do", "dynamic", "else", "enum", "export", "extends",
    "extension", "external", "factory", "false", "final", "finally",
    "for", "Function", "get", "hide", "if", "implements", "import",
    "in", "interface", "is", "late", "library", "mixin", "new", "null",
    "on", "operator", "part", "required", "rethrow", "return", "set",
    "show", "static", "super", "switch", "sync", "this", "throw",
    "true", "try", "typedef", "var", "void", "when", "while", "with",
    "yield", "print", "identical",
  }

  RECEIVER_CALL_REGEX       = /([A-Za-z_][A-Za-z0-9_]*(?:\s*(?:\?\.|!\.|\.)\s*[A-Za-z_][A-Za-z0-9_]*)+)\s*(?:<[^;\n{}]*>)?\s*\(/
  BARE_CALL_REGEX           = /(?<![A-Za-z0-9_.!?<])([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^;\n{}]*>)?\s*\(/
  DECLARATION_CONTEXT_REGEX = /(?:^|[;{}])\s*((?:[A-Z][A-Za-z0-9_]*|void|int|double|num|bool|String|Future|Stream|Map|List|Set|Iterable|Object|dynamic)(?:\s*<[^;{}()=]*>)?\??)\s+$/

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry
    state = INITIAL_STATE

    body.each_line.with_index do |line, index|
      stripped, state = strip_non_code_with_state(line, state)
      scan_line(stripped, file_path, start_line + index, entries)
    end

    dedup_entries(entries)
  end

  def extract_body_after(source : String, start_index : Int32, limit : Int32 = source.bytesize) : BodyInfo?
    arrow_index = find_next_arrow(source, start_index, limit)
    open_brace = find_next_code_char(source, '{', start_index, limit)
    semicolon = find_next_code_char(source, ';', start_index, limit)

    if arrow_index && (!semicolon || arrow_index < semicolon) && (!open_brace || arrow_index < open_brace)
      body_start = arrow_index + 2
      body_end = semicolon || limit
      # body_start/body_end are BYTE offsets (the scanners use byte_at), so slice
      # by bytes — char-indexing here corrupts/crashes on multi-byte UTF-8 source.
      return {source.byte_slice(body_start, body_end - body_start), body_start, body_end}
    end

    if open_brace && (!semicolon || open_brace < semicolon)
      close_brace = find_matching_delimiter(source, open_brace, '{', '}', limit)
      return unless close_brace

      body_start = open_brace + 1
      # byte offsets -> slice by bytes (see note above).
      return {source.byte_slice(body_start, close_brace - body_start), body_start, close_brace + 1}
    end

    nil
  end

  def find_next_code_char(source : String, target : Char, start_index : Int32, limit : Int32 = source.bytesize) : Int32?
    i = start_index
    while i < limit
      char = source.byte_at(i).unsafe_chr
      if raw_string_prefix?(source, i, limit)
        i = skip_string(source, i + 1, limit, raw: true)
      else
        case char
        when '"', '\''
          i = skip_string(source, i, limit)
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
      if raw_string_prefix?(source, i, limit)
        i = skip_string(source, i + 1, limit, raw: true)
      else
        case char
        when '"', '\''
          i = skip_string(source, i, limit)
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

    line.scan(RECEIVER_CALL_REGEX) do |match|
      candidates << {match.begin(1) || 0, normalize_name(match[1])}
    end

    line.scan(BARE_CALL_REGEX) do |match|
      position = match.begin(1) || 0
      next if declaration_callee?(line, position)

      candidates << {position, match[1]}
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

    last = name.split("?.").last.split("!.").last.split('.').last
    RESERVED.includes?(last)
  end

  private def declaration_callee?(line : String, position : Int32) : Bool
    return false if position <= 0

    before = line[0...position]
    return false if before.strip.empty?

    !!before.match(DECLARATION_CONTEXT_REGEX)
  end

  private def find_next_arrow(source : String, start_index : Int32, limit : Int32) : Int32?
    i = start_index
    while i + 1 < limit
      char = source.byte_at(i).unsafe_chr
      if raw_string_prefix?(source, i, limit)
        i = skip_string(source, i + 1, limit, raw: true)
      else
        case char
        when '"', '\''
          i = skip_string(source, i, limit)
        when '/'
          next_char = source.byte_at(i + 1).unsafe_chr
          if next_char == '/'
            i = skip_line_comment(source, i, limit)
          elsif next_char == '*'
            i = skip_block_comment(source, i, limit)
          end
        when '='
          return i if source.byte_at(i + 1).unsafe_chr == '>'
        end
      end
      i += 1
    end

    nil
  end

  private def strip_non_code_with_state(line : String, state : StripState) : Tuple(String, StripState)
    chars = line.chars
    block_comment = state[:block_comment]
    triple_quote = state[:triple_quote]
    index = 0
    stripped = String::Builder.new

    while index < chars.size
      char = chars[index]

      if block_comment
        if char == '*' && chars[index + 1]? == '/'
          block_comment = false
          index += 1
        end
      elsif triple_quote != '\0'
        if triple_delimiter?(chars, index, triple_quote)
          triple_quote = '\0'
          index += 2
        end
      elsif raw_string_prefix?(chars, index)
        quote = chars[index + 1]
        if triple_delimiter?(chars, index + 1, quote)
          index = skip_triple_string(chars, index + 1, quote)
        else
          index = skip_quoted_string(chars, index + 1, quote, raw: true)
        end
      elsif char == '"' || char == '\''
        if triple_delimiter?(chars, index, char)
          triple_quote = char
          index += 2
        else
          index = skip_quoted_string(chars, index, char)
        end
      elsif char == '/' && chars[index + 1]? == '/'
        break
      elsif char == '/' && chars[index + 1]? == '*'
        block_comment = true
        index += 1
      else
        stripped << char
      end

      index += 1
    end

    {stripped.to_s, {block_comment: block_comment, triple_quote: triple_quote}}
  end

  private def raw_string_prefix?(chars : Array(Char), index : Int32) : Bool
    return false unless chars[index]? == 'r'
    quote = chars[index + 1]?
    return false unless quote == '"' || quote == '\''
    return true if index == 0

    !identifier_char?(chars[index - 1])
  end

  private def raw_string_prefix?(source : String, index : Int32, limit : Int32) : Bool
    return false unless source.byte_at(index).unsafe_chr == 'r'
    return false unless index + 1 < limit

    quote = source.byte_at(index + 1).unsafe_chr
    return false unless quote == '"' || quote == '\''
    return true if index == 0

    !identifier_char?(source.byte_at(index - 1).unsafe_chr)
  end

  private def identifier_char?(char : Char) : Bool
    char.alphanumeric? || char == '_'
  end

  private def triple_delimiter?(chars : Array(Char), index : Int32, quote : Char) : Bool
    chars[index]? == quote && chars[index + 1]? == quote && chars[index + 2]? == quote
  end

  private def skip_quoted_string(chars : Array(Char), index : Int32, quote : Char, raw : Bool = false) : Int32
    i = index + 1
    escaping = false

    while i < chars.size
      char = chars[i]
      if !raw && escaping
        escaping = false
      elsif !raw && char == '\\'
        escaping = true
      elsif char == quote
        return i
      end
      i += 1
    end

    chars.size - 1
  end

  private def skip_triple_string(chars : Array(Char), index : Int32, quote : Char) : Int32
    i = index + 3
    while i < chars.size
      return i + 2 if triple_delimiter?(chars, i, quote)

      i += 1
    end

    chars.size - 1
  end

  private def skip_string(source : String, index : Int32, limit : Int32, raw : Bool = false) : Int32
    quote = source.byte_at(index).unsafe_chr
    if index + 2 < limit &&
       source.byte_at(index + 1).unsafe_chr == quote &&
       source.byte_at(index + 2).unsafe_chr == quote
      return skip_triple_string(source, index, quote, limit)
    end

    i = index + 1
    escaping = false
    while i < limit
      char = source.byte_at(i).unsafe_chr
      if !raw && escaping
        escaping = false
      elsif !raw && char == '\\'
        escaping = true
      elsif char == quote
        return i
      end
      i += 1
    end

    limit - 1
  end

  private def skip_triple_string(source : String, index : Int32, quote : Char, limit : Int32) : Int32
    i = index + 3
    while i + 2 < limit
      if source.byte_at(i).unsafe_chr == quote &&
         source.byte_at(i + 1).unsafe_chr == quote &&
         source.byte_at(i + 2).unsafe_chr == quote
        return i + 2
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
    while i + 1 < limit
      return i + 1 if source.byte_at(i).unsafe_chr == '*' &&
                      source.byte_at(i + 1).unsafe_chr == '/'

      i += 1
    end

    limit - 1
  end
end
