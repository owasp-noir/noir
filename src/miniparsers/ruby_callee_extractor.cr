require "../models/endpoint"

module Noir::RubyCalleeExtractor
  extend self

  alias Entry = Tuple(String, String, Int32)

  RESERVED = Set{
    "alias", "and", "begin", "break", "case", "class", "def",
    "defined?", "do", "else", "elsif", "end", "ensure", "false",
    "for", "if", "in", "module", "next", "nil", "not", "or",
    "redo", "rescue", "retry", "return", "self", "super", "then",
    "true", "undef", "unless", "until", "when", "while", "yield",
  }

  RECEIVER_CALL_REGEX = /((?:@{1,2})?[A-Za-z_][\w]*(?:::[A-Za-z_][\w]*)*(?:\.[A-Za-z_][\w]*[!?=]?)+)\s*(?:\(|\b|$)/
  BARE_CALL_REGEX     = /(?<![.\w:])([a-z_][\w]*[!?=]?)(?:\s*\(|(?=\s+(?:[:'"]|@{1,2}[A-Za-z_]|[A-Za-z_][\w]*[!?=]?)))/

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry

    body.lines.each_with_index do |line, index|
      scan_line(strip_comment(line), file_path, start_line + index, entries)
    end

    dedup_entries(entries)
  end

  def attach_to(endpoint : Endpoint, callees : Array(Entry))
    callees.each do |name, path, line|
      endpoint.push_callee(Callee.new(name, path: path, line: line))
    end
  end

  private def scan_line(line : String, file_path : String, line_number : Int32, entries : Array(Entry))
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

    last = name.split('.').last
    RESERVED.includes?(last)
  end

  def strip_comment(line : String, preserve_strings : Bool = false) : String
    stripped = String::Builder.new
    in_string = false
    escaped = false
    quote = '\0'

    line.each_char do |char|
      if in_string
        if escaped
          stripped << (preserve_strings ? char : ' ')
          escaped = false
        elsif char == '\\'
          stripped << (preserve_strings ? char : ' ')
          escaped = true
        elsif char == quote
          stripped << char
          in_string = false
        else
          stripped << (preserve_strings ? char : ' ')
        end
      elsif char == '"' || char == '\''
        in_string = true
        quote = char
        stripped << char
      elsif char == '#'
        return stripped.to_s
      else
        stripped << char
      end
    end

    stripped.to_s
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
