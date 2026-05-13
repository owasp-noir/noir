require "../models/endpoint"

module Noir::CSharpCalleeExtractor
  extend self

  alias Entry = Tuple(String, String, Int32)

  RESERVED = Set{
    "as", "await", "base", "case", "catch", "checked", "default",
    "delegate", "do", "else", "event", "explicit", "finally",
    "fixed", "for", "foreach", "if", "implicit", "is", "lock",
    "nameof", "new", "operator", "return", "sizeof", "switch",
    "this", "throw", "typeof", "unchecked", "unsafe", "using", "while",
  }

  ROUTE_BUILDER_METHODS = Set{
    "Map", "MapGet", "MapPost", "MapPut", "MapDelete", "MapPatch",
    "MapHead", "MapOptions", "MapMethods",
  }

  CALL_REGEX = /((?:[A-Za-z_][\w]*)(?:\s*\.\s*[A-Za-z_][\w]*)*)\s*(?:<[^>\n]+>)?\s*\(/

  def callees_for_block(block : String,
                        file_path : String,
                        start_line : Int32,
                        *,
                        skip_first_line : Bool = false) : Array(Entry)
    entries = [] of Entry

    block.lines.each_with_index do |line, index|
      if skip_first_line && index == 0
        if brace_index = line.index('{')
          remainder = line[(brace_index + 1)..]? || ""
          scan_line(strip_line_comment(remainder), file_path, start_line + index, entries)
        end
        next
      end

      scan_line(strip_line_comment(line), file_path, start_line + index, entries)
    end

    dedup_entries(entries)
  end

  def attach_to(endpoint : Endpoint, callees : Array(Entry))
    callees.each do |name, path, line|
      endpoint.push_callee(Callee.new(name, path: path, line: line))
    end
  end

  private def scan_line(line : String, file_path : String, line_number : Int32, entries : Array(Entry))
    code = line.strip
    return if code.empty?

    code.scan(CALL_REGEX) do |match|
      name = match[1].gsub(/\s+/, "")
      next if skip_callee?(name)

      entries << {name, file_path, line_number}
    end
  end

  private def skip_callee?(name : String) : Bool
    return true if name.empty?

    last = name.split('.').last
    return true if RESERVED.includes?(last)
    return true if ROUTE_BUILDER_METHODS.includes?(last)

    false
  end

  private def strip_line_comment(line : String) : String
    in_string = false
    escaped = false

    line.each_char_with_index do |char, index|
      if in_string
        if escaped
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif char == '"'
          in_string = false
        end
      elsif char == '"'
        in_string = true
      elsif char == '/' && line[index + 1]? == '/'
        return line[0, index]
      end
    end

    line
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
