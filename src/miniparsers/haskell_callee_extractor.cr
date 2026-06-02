require "../models/endpoint"

module Noir::HaskellCalleeExtractor
  extend self

  alias Entry = Tuple(String, String, Int32)
  alias FunctionBody = NamedTuple(name: String, body: String, path: String, start_line: Int32)

  RESERVED = Set{
    "as", "case", "class", "data", "default", "deriving", "do", "else",
    "family", "forall", "foreign", "hiding", "if", "import", "in",
    "infix", "infixl", "infixr", "instance", "let", "module", "newtype",
    "of", "qualified", "then", "type", "where",
    "return", "pure", "fmap", "map", "filter", "foldl", "foldr", "id",
    "const", "show", "read", "print", "putStrLn", "length", "null",
    "not", "and", "or", "maybe", "either", "fst", "snd",
  }

  QUALIFIED_CALL_REGEX = /(?<![A-Za-z0-9_'.])((?:[A-Z][A-Za-z0-9_']*\.)+[a-z_][A-Za-z0-9_']*)\b/
  STATEMENT_CALL_REGEX = /^\s*([a-z_][A-Za-z0-9_']*)\b(?=\s|$|\()/
  BIND_CALL_REGEX      = /(?:<-|=)\s*([a-z_][A-Za-z0-9_']*)\b(?=\s|$|\()/
  DOLLAR_CALL_REGEX    = /\$\s*([a-z_][A-Za-z0-9_']*)\b(?=\s|$|\()/
  PAREN_CALL_REGEX     = /[(,]\s*([a-z_][A-Za-z0-9_']*)\b(?=\s|$|\()/
  BRANCH_CALL_REGEX    = /(?:->|\bthen\b|\belse\b)\s*([a-z_][A-Za-z0-9_']*)\b(?=\s|$|\()/

  def function_bodies(content : String, file_path : String) : Array(FunctionBody)
    cleaned = strip_non_code(content)
    lines = cleaned.lines
    results = [] of FunctionBody
    index = 0

    while index < lines.size
      line = lines[index]
      match = line.match(/^([a-z_][A-Za-z0-9_']*)\b.*=/)
      unless match
        index += 1
        next
      end

      name = match[1]
      if skip_callee?(name)
        index += 1
        next
      end

      equals_index = line.index('=')
      unless equals_index
        index += 1
        next
      end

      # A `::` before the `=` marks a type signature (`foo :: (C a) => a`), not a
      # definition. Only inspect the head; an inline annotation in the body
      # (e.g. `apiSwagger = toSwagger (Proxy :: Proxy API)`) is a real binding.
      if line[0...equals_index].includes?("::")
        index += 1
        next
      end

      body_lines = [line[(equals_index + 1)..]? || ""]
      start_line = index + 1
      cursor = index + 1

      while cursor < lines.size
        next_line = lines[cursor]
        break if top_level_declaration?(next_line) && !same_function_equation?(next_line, name)

        body_lines << next_line
        cursor += 1
      end

      results << {
        name:       name,
        body:       body_lines.join("\n"),
        path:       file_path,
        start_line: start_line,
      }
      index = cursor
    end

    results
  end

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry
    stripped_body = strip_non_code(body)

    stripped_body.each_line.with_index do |line, offset|
      scan_line(line, file_path, start_line + offset, entries)
    end

    dedup_entries(entries)
  end

  def attach_to(endpoint : Endpoint, callees : Array(Entry))
    callees.each do |name, path, line|
      endpoint.push_callee(Callee.new(name, path: path, line: line))
    end
  end

  private def scan_line(line : String, file_path : String, line_number : Int32, entries : Array(Entry))
    candidates = [] of Tuple(Int32, String)

    scan_candidates(line, QUALIFIED_CALL_REGEX, candidates)
    scan_statement_candidates(line, candidates)
    scan_candidates(line, BIND_CALL_REGEX, candidates)
    scan_candidates(line, DOLLAR_CALL_REGEX, candidates)
    scan_candidates(line, PAREN_CALL_REGEX, candidates)
    scan_candidates(line, BRANCH_CALL_REGEX, candidates)

    candidates.sort_by! { |position, _| position }
    candidates.each do |_, name|
      next if skip_callee?(name)

      entries << {name, file_path, line_number}
    end
  end

  private def scan_statement_candidates(line : String, candidates : Array(Tuple(Int32, String)))
    line.scan(STATEMENT_CALL_REGEX) do |match|
      position = match.begin(1) || 0
      name = match[1]
      next if assignment_lhs?(line, position, name)

      candidates << {position, name}
    end
  end

  private def scan_candidates(line : String, regex : Regex, candidates : Array(Tuple(Int32, String)))
    line.scan(regex) do |match|
      candidates << {match.begin(1) || 0, match[1]}
    end
  end

  private def assignment_lhs?(line : String, position : Int32, name : String) : Bool
    rest = line[(position + name.size)..]? || ""
    !!rest.match(/\A\s*(?:<-|=|::)/)
  end

  private def top_level_declaration?(line : String) : Bool
    stripped = line.strip
    return false if stripped.empty?
    return false if line[0].whitespace?

    return true if stripped.match(/^(?:module|import|data|newtype|type|class|instance)\b/)
    !!stripped.match(/^[A-Za-z_][A-Za-z0-9_']*\b.*(?:=|::)/)
  end

  private def same_function_equation?(line : String, name : String) : Bool
    !!line.match(/^#{Regex.escape(name)}\b.*=/)
  end

  private def skip_callee?(name : String) : Bool
    return true if name.empty?
    return true if name == "_"

    RESERVED.includes?(name.split('.').last)
  end

  private def strip_non_code(source : String) : String
    index = 0
    stripped = String::Builder.new

    while index < source.size
      char = source[index]

      if index + 1 < source.size && char == '-' && source[index + 1] == '-'
        index = append_blanks_until_line_end(stripped, source, index)
        next
      end

      if index + 1 < source.size && char == '{' && source[index + 1] == '-'
        finish = skip_block_comment(source, index)
        append_blanks(stripped, source, index, finish)
        index = finish
        next
      end

      if char == '"'
        finish = skip_string(source, index)
        append_blanks(stripped, source, index, finish)
        index = finish
        next
      end

      if char == '\'' && char_literal_start?(source, index)
        finish = skip_char(source, index)
        append_blanks(stripped, source, index, finish)
        index = finish
        next
      end

      if quasiquote_start?(source, index)
        finish = skip_quasiquote(source, index)
        append_blanks(stripped, source, index, finish)
        index = finish
        next
      end

      stripped << char
      index += 1
    end

    stripped.to_s
  end

  private def char_literal_start?(source : String, start : Int32) : Bool
    return false if start + 2 >= source.size
    return false if source[start + 1] == '['

    finish = skip_char(source, start)
    return false if finish >= source.size
    finish - start <= 8
  end

  private def append_blanks_until_line_end(stripped : String::Builder, source : String, start : Int32) : Int32
    index = start
    while index < source.size && source[index] != '\n'
      stripped << ' '
      index += 1
    end
    index
  end

  private def append_blanks(stripped : String::Builder, source : String, start : Int32, finish : Int32)
    index = start
    while index < finish && index < source.size
      stripped << (source[index] == '\n' ? '\n' : ' ')
      index += 1
    end
  end

  private def skip_block_comment(source : String, start : Int32) : Int32
    index = start + 2
    depth = 1
    while index < source.size && depth > 0
      if index + 1 < source.size && source[index] == '{' && source[index + 1] == '-'
        depth += 1
        index += 2
      elsif index + 1 < source.size && source[index] == '-' && source[index + 1] == '}'
        depth -= 1
        index += 2
      else
        index += 1
      end
    end
    index
  end

  private def skip_string(source : String, start : Int32) : Int32
    index = start + 1
    while index < source.size
      if source[index] == '\\' && index + 1 < source.size
        index += 2
        next
      end
      return index + 1 if source[index] == '"'

      index += 1
    end
    source.size
  end

  private def skip_char(source : String, start : Int32) : Int32
    index = start + 1
    while index < source.size
      if source[index] == '\\' && index + 1 < source.size
        index += 2
        next
      end
      return index + 1 if source[index] == '\''

      index += 1
    end
    source.size
  end

  private def quasiquote_start?(source : String, start : Int32) : Bool
    return false unless source[start] == '['

    index = start + 1
    return false unless source[index]? && (source[index].ascii_letter? || source[index] == '_')

    while index < source.size && (source[index].alphanumeric? || source[index] == '_' || source[index] == '\'')
      index += 1
    end

    index < source.size && source[index] == '|'
  end

  private def skip_quasiquote(source : String, start : Int32) : Int32
    index = start + 1
    while index + 1 < source.size
      return index + 2 if source[index] == '|' && source[index + 1] == ']'

      index += 1
    end
    source.size
  end

  private def dedup_entries(entries : Array(Entry)) : Array(Entry)
    seen = Set(Entry).new
    entries.select { |entry| seen.add?(entry) }
  end
end
