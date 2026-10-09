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

    entries.uniq
  end

  # Blanks comments and string literals to spaces (char positions are kept),
  # carrying block-comment / `"""` state across lines. A literal ends where
  # Swift ends it: past `\( … )` interpolation (which may hold quotes and
  # braces) and at the matching `"#` of a raw `#"…"#`. `keep_strings` keeps
  # single-line literals verbatim, for route scanners that read the path
  # out of the stripped line.
  def strip_non_code_with_state(line : String,
                                block_comment_depth : Int32,
                                in_multiline_string : Bool,
                                keep_strings : Bool = false) : Tuple(String, Int32, Bool)
    chars = line.chars
    size = chars.size
    index = 0
    stripped = String::Builder.new

    while index < size
      char = chars[index]
      next_char = chars[index + 1]?
      third_char = chars[index + 2]?

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
      elsif char == '#' && chars[index + (hashes = hash_run(chars, index))]? != '"'
        # Not a raw string (`#if`, `#selector`): emit the whole run at once.
        hashes.times { stripped << '#' }
        index += hashes
        next
      elsif char == '"' || char == '#'
        hashes = char == '"' ? 0 : hash_run(chars, index)
        quote = index + hashes
        if chars[quote + 1]? == '"' && chars[quote + 2]? == '"'
          in_multiline_string = true
          append_spaces(stripped, hashes + 3)
          index = quote + 3
          next
        end
        finish = string_literal_end(chars, quote + 1, hashes)
        if keep_strings
          (index...finish).each { |i| stripped << chars[i] }
        else
          append_spaces(stripped, finish - index)
        end
        index = finish
        next
      elsif char == '/' && chars[index + 1]? == '/'
        append_spaces(stripped, size - index)
        return {stripped.to_s, block_comment_depth, in_multiline_string}
      elsif char == '/' && chars[index + 1]? == '*'
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

  # Length of the `#` run at `index`; a raw string opens when `"` follows.
  private def hash_run(chars : Array(Char), index : Int32) : Int32
    hashes = 0
    while chars[index + hashes]? == '#'
      hashes += 1
    end
    hashes
  end

  # Index just past the literal whose body starts at `index`, honouring
  # escapes, `\( … )` interpolation (which may itself hold strings, so a
  # quote or brace in there does not end anything) and raw `#` delimiters
  # (`\#(` interpolates in `#"…"#`). Frames: a string with N hashes is N
  # (>= 0); an interpolation at paren depth D is -D. Iterative so hostile
  # nesting cannot overflow the stack. Unterminated runs to end of line.
  private def string_literal_end(chars : Array(Char), index : Int32, hashes : Int32) : Int32
    size = chars.size
    stack = [hashes]
    i = index
    while i < size
      top = stack.last
      char = chars[i]
      if top >= 0
        if char == '\\' || char == '"'
          j = i + 1
          matched = 0
          while matched < top && chars[j]? == '#'
            matched += 1
            j += 1
          end
          if matched == top
            if char == '"'
              stack.pop
              return j if stack.empty?
              i = j
            elsif chars[j]? == '('
              stack << -1
              i = j + 1
            else
              i = j + 1 # escaped char
            end
            next
          end
        end
        i += 1
      else
        if char == '"' || char == '#'
          raw = char == '#' ? hash_run(chars, i) : 0
          stack << raw if chars[i + raw]? == '"'
          i += raw + (chars[i + raw]? == '"' ? 1 : 0)
          next
        elsif char == '('
          stack[-1] = top - 1
        elsif char == ')'
          top == -1 ? stack.pop : (stack[-1] = top + 1)
        end
        i += 1
      end
    end
    size
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
