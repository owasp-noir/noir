require "../models/endpoint"
require "./callee_extractor_base"

module Noir::CrystalCalleeExtractor
  extend self
  include Noir::CalleeExtractorBase

  RESERVED = Set{
    "abstract", "alias", "annotation", "as", "asm", "begin",
    "break", "case", "class", "def", "do", "else", "elsif",
    "end", "ensure", "enum", "extend", "false", "for", "fun",
    "if", "in", "include", "lib", "macro", "module", "next",
    "nil", "of", "out", "private", "protected", "require",
    "rescue", "return", "self", "struct", "super", "then",
    "true", "type", "union", "unless", "until", "when", "while",
    "with", "yield",
  }

  RECEIVER_CALL_REGEX = /((?:@{1,2})?[A-Za-z_]\w*(?:::[A-Za-z_]\w*)*(?:\.[A-Za-z_]\w*[!?=]?)+)\s*(?:\(|\b|$)/
  BARE_CALL_REGEX     = /(?<![.\w:])([a-z_]\w*[!?=]?)(?:\s*\(|(?=\s+(?:[:'"]|@{1,2}[A-Za-z_]|[A-Za-z_]\w*[!?=]?)))/

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry

    body.lines.each_with_index do |line, index|
      scan_line(strip_comment(line), file_path, start_line + index, entries)
    end

    dedup_entries(entries)
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

  def strip_comment(line : String) : String
    in_string = false
    escaped = false
    quote = '\0'

    line.each_char_with_index do |char, index|
      if in_string
        if escaped
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif char == quote
          in_string = false
        end
      elsif char == '"' || char == '\''
        in_string = true
        quote = char
      elsif char == '#'
        return line[0, index]
      end
    end

    line
  end
end
