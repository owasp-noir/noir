require "../models/endpoint"

module Noir::PhpCalleeExtractor
  extend self

  alias Entry = Tuple(String, String, Int32)

  RESERVED = Set{
    "array", "catch", "class", "clone", "declare", "die", "echo",
    "elseif", "empty", "eval", "exit", "fn", "for", "foreach",
    "function", "global", "if", "include", "include_once", "isset",
    "list", "match", "print", "require", "require_once", "return",
    "static", "switch", "throw", "trait", "try", "unset", "while",
  }

  CLASS_PROPERTY_CALL_REGEX = /((?:\\?[A-Za-z_]\w*\\?)*[A-Za-z_]\w*::\$\w+(?:\s*->\s*[A-Za-z_]\w*\s*(?:\(\s*\))?)*\s*->\s*[A-Za-z_]\w*)\s*\(/
  OBJECT_CALL_REGEX         = /(?<!:)(\$[A-Za-z_]\w*(?:\s*->\s*[A-Za-z_]\w*\s*(?:\(\s*\))?)*\s*->\s*[A-Za-z_]\w*)\s*\(/
  STATIC_CALL_REGEX         = /((?:\\?[A-Za-z_]\w*\\?)*[A-Za-z_]\w*(?:::[A-Za-z_]\w*)+)\s*\(/
  BARE_CALL_REGEX           = /(?<![>\w:$\\])((?:\\?[A-Za-z_]\w*\\)*\\?[A-Za-z_]\w*)\s*\(/

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry

    in_block_comment = false

    body.lines.each_with_index do |line, index|
      sanitized, in_block_comment = sanitize_line(line, in_block_comment)
      scan_line(sanitized, file_path, start_line + index, entries)
    end

    dedup_entries(entries)
  end

  def attach_to(endpoint : Endpoint, callees : Array(Entry))
    callees.each do |name, path, line|
      endpoint.push_callee(Callee.new(name, path: path, line: line))
    end
  end

  private def scan_line(line : String, file_path : String, line_number : Int32, entries : Array(Entry))
    line.scan(CLASS_PROPERTY_CALL_REGEX) do |match|
      name = normalize_object_call(match[1])
      next if skip_callee?(name)

      entries << {name, file_path, line_number}
    end

    line.scan(OBJECT_CALL_REGEX) do |match|
      name = normalize_object_call(match[1])
      next if skip_callee?(name)

      entries << {name, file_path, line_number}
    end

    line.scan(STATIC_CALL_REGEX) do |match|
      name = normalize_static_call(match[1])
      next if skip_callee?(name)

      entries << {name, file_path, line_number}
    end

    line.scan(BARE_CALL_REGEX) do |match|
      name = match[1]
      next if skip_callee?(name)

      entries << {name, file_path, line_number}
    end
  end

  private def normalize_object_call(name : String) : String
    name.gsub(/\s+/, "")
  end

  private def normalize_static_call(name : String) : String
    name.gsub(/\s+/, "")
  end

  private def skip_callee?(name : String) : Bool
    return true if name.empty?
    return false if name.includes?("->") || name.includes?("::")

    RESERVED.includes?(name.downcase)
  end

  def strip_comment(line : String) : String
    sanitized, _ = sanitize_line(line, false)
    sanitized
  end

  private def sanitize_line(line : String, in_block_comment : Bool) : Tuple(String, Bool)
    sanitized = String.build do |io|
      in_string = false
      escaped = false
      quote = '\0'
      index = 0

      while index < line.size
        char = line[index]
        next_char = line[index + 1]?

        if in_block_comment
          if char == '*' && next_char == '/'
            io << "  "
            in_block_comment = false
            index += 2
          else
            io << ' '
            index += 1
          end
        elsif in_string
          io << ' '
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            in_string = false
          end
          index += 1
        elsif char == '/' && next_char == '*'
          io << "  "
          in_block_comment = true
          index += 2
        elsif char == '/' && next_char == '/'
          io << " " * (line.size - index)
          index = line.size
        elsif char == '#'
          io << " " * (line.size - index)
          index = line.size
        elsif char == '"' || char == '\''
          io << ' '
          in_string = true
          quote = char
          index += 1
        else
          io << char
          index += 1
        end
      end
    end

    {sanitized, in_block_comment}
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
