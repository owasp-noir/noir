require "../models/endpoint"

module Noir::RustCalleeExtractor
  extend self

  alias Entry = Tuple(String, String, Int32)

  RESERVED = Set{
    "as", "async", "await", "break", "const", "continue", "crate",
    "dyn", "else", "enum", "extern", "false", "fn", "for", "if",
    "impl", "in", "let", "loop", "match", "mod", "move", "mut",
    "pub", "ref", "return", "self", "Self", "static", "struct",
    "super", "trait", "true", "type", "unsafe", "use", "where",
    "while", "Ok", "Err", "Some", "None", "format", "format!",
    "vec", "vec!", "println", "println!",
  }

  PATH_CALL_REGEX     = /((?:[A-Za-z_]\w*::)+[A-Za-z_]\w*[!?]?)\s*(?:\(|!)/
  RECEIVER_CALL_REGEX = /([A-Za-z_]\w*(?:\.[A-Za-z_]\w*[!?]?)+)\s*\(/
  BARE_CALL_REGEX     = /(?<![.\w:])([A-Za-z_]\w*[!?]?)(?:\s*\(|!)/

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry
    in_block_comment = false

    body.lines.each_with_index do |line, index|
      stripped, in_block_comment = strip_comment_with_state(line, in_block_comment)
      scan_line(stripped, file_path, start_line + index, entries)
    end

    dedup_entries(entries)
  end

  def attach_to(endpoint : Endpoint, callees : Array(Entry))
    callees.each do |name, path, line|
      endpoint.push_callee(Callee.new(name, path: path, line: line))
    end
  end

  def strip_comment(line : String, in_block_comment : Bool = false, preserve_strings : Bool = false) : String
    stripped, _ = strip_comment_with_state(line, in_block_comment, preserve_strings)
    stripped
  end

  def strip_comment_with_state(line : String, in_block_comment : Bool, preserve_strings : Bool = false) : Tuple(String, Bool)
    in_string = false
    escaped = false
    quote = '\0'
    index = 0
    stripped = String::Builder.new

    while index < line.size
      char = line[index]
      if in_block_comment
        if char == '*' && line[index + 1]? == '/'
          in_block_comment = false
          index += 1
        end
      elsif in_string
        stripped << char if preserve_strings
        if escaped
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif char == quote
          in_string = false
        end
      elsif char == '"'
        in_string = true
        quote = char
        stripped << char if preserve_strings
      elsif char == '/' && line[index + 1]? == '/'
        return {stripped.to_s, in_block_comment}
      elsif char == '/' && line[index + 1]? == '*'
        in_block_comment = true
        index += 1
      else
        stripped << char
      end
      index += 1
    end

    {stripped.to_s, in_block_comment}
  end

  private def scan_line(line : String, file_path : String, line_number : Int32, entries : Array(Entry))
    line.scan(PATH_CALL_REGEX) do |match|
      name = match[1]
      next if skip_callee?(name)

      entries << {name, file_path, line_number}
    end

    line.scan(RECEIVER_CALL_REGEX) do |match|
      name = match[1]
      next if skip_callee?(name)

      entries << {name, file_path, line_number}
    end

    line.scan(BARE_CALL_REGEX) do |match|
      name = match[1]
      next if skip_callee?(name)

      entries << {name, file_path, line_number}
    end
  end

  private def skip_callee?(name : String) : Bool
    return true if name.empty?

    last = name.split('.').last.split("::").last
    RESERVED.includes?(last) && (!name.includes?("::") || last.includes?('!'))
  end

  private def dedup_entries(entries : Array(Entry)) : Array(Entry)
    seen = Set(String).new
    entries.select do |name, path, line|
      key = "#{name}\0#{path}\0#{line}"
      if seen.includes?(key)
        false
      else
        seen.add(key)
        true
      end
    end
  end
end
