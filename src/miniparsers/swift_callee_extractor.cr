require "../models/endpoint"
require "./callee_extractor_base"

module Noir::SwiftCalleeExtractor
  extend self
  include Noir::CalleeExtractorBase

  RESERVED = Set{
    "as", "associatedtype", "break", "case", "catch", "class",
    "continue", "default", "defer", "deinit", "do", "else",
    "enum", "extension", "fallthrough", "false", "fileprivate",
    "for", "func", "guard", "if", "import", "in", "init",
    "inout", "internal", "is", "let", "nil", "open", "operator",
    "private", "protocol", "public", "repeat", "return", "self",
    "Self", "static", "struct", "subscript", "super", "switch",
    "throw", "throws", "true", "try", "typealias", "var", "where",
    "while", "await",
  }

  RECEIVER_CALL_REGEX = /([A-Za-z_]\w*(?:\??\.[A-Za-z_]\w*)+)\s*(\(|\{)/
  BARE_CALL_REGEX     = /(?<![.\w])([A-Za-z_]\w*)\s*(\(|\{)/

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry
    block_comment_depth = 0
    in_multiline_string = false

    body.lines.each_with_index do |line, index|
      stripped, block_comment_depth, in_multiline_string = strip_non_code_with_state(
        line,
        block_comment_depth,
        in_multiline_string
      )
      scan_line(stripped, file_path, start_line + index, entries)
    end

    dedup_entries(entries)
  end

  def strip_comment(line : String, in_block_comment : Bool = false) : String
    stripped, _ = strip_comment_with_state(line, in_block_comment)
    stripped
  end

  def strip_comment_with_state(line : String, in_block_comment : Bool) : Tuple(String, Bool)
    stripped, block_comment_depth, _ = strip_non_code_with_state(line, in_block_comment ? 1 : 0, false)
    {stripped, block_comment_depth > 0}
  end

  def strip_non_code_with_state(line : String,
                                block_comment_depth : Int32,
                                in_multiline_string : Bool) : Tuple(String, Int32, Bool)
    in_string = false
    escaped = false
    index = 0
    stripped = String::Builder.new

    while index < line.size
      char = line[index]
      next_char = line[index + 1]?
      third_char = line[index + 2]?

      if block_comment_depth > 0
        if char == '/' && next_char == '*'
          block_comment_depth += 1
          append_spaces(stripped, 2)
          index += 2
          next
        elsif char == '*' && next_char == '/'
          block_comment_depth -= 1
          append_spaces(stripped, 2)
          index += 2
          next
        end
        stripped << ' '
      elsif in_multiline_string
        if char == '"' && next_char == '"' && third_char == '"'
          in_multiline_string = false
          append_spaces(stripped, 3)
          index += 3
          next
        end
        stripped << ' '
      elsif in_string
        if escaped
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif char == '"'
          in_string = false
        end
        stripped << ' '
      elsif char == '"'
        if next_char == '"' && third_char == '"'
          in_multiline_string = true
          append_spaces(stripped, 3)
          index += 3
          next
        else
          in_string = true
        end
        stripped << ' '
      elsif char == '/' && line[index + 1]? == '/'
        append_spaces(stripped, line.size - index)
        return {stripped.to_s, block_comment_depth, in_multiline_string}
      elsif char == '/' && line[index + 1]? == '*'
        block_comment_depth += 1
        append_spaces(stripped, 2)
        index += 2
        next
      else
        stripped << char
      end
      index += 1
    end

    {stripped.to_s, block_comment_depth, in_multiline_string}
  end

  private def append_spaces(stripped : String::Builder, count : Int32)
    count.times { stripped << ' ' }
  end

  private def scan_line(line : String, file_path : String, line_number : Int32, entries : Array(Entry))
    line.scan(RECEIVER_CALL_REGEX) do |match|
      name = match[1]
      delimiter = match[2]
      if delimiter == "{"
        name_start = match.begin(1) || 0
        next if control_flow_condition?(line, name_start)
      end
      next if skip_callee?(name)

      entries << {name, file_path, line_number}
    end

    line.scan(BARE_CALL_REGEX) do |match|
      name = match[1]
      delimiter = match[2]
      if delimiter == "{"
        name_start = match.begin(1) || 0
        next if control_flow_condition?(line, name_start)
      end
      next if skip_callee?(name)

      entries << {name, file_path, line_number}
    end
  end

  private def skip_callee?(name : String) : Bool
    return true if name.empty?

    last = name.split('.').last
    RESERVED.includes?(last)
  end

  private def control_flow_condition?(line : String, name_start : Int32) : Bool
    prefix = line[0...name_start].strip
    !!prefix.match(/\b(if|guard|while|for|switch|catch|else|do)$/)
  end
end
