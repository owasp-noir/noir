require "../models/endpoint"
require "../utils/groovy_literal_scanner"

module Noir::GroovyCalleeExtractor
  extend self

  alias Entry = Tuple(String, String, Int32)

  RESERVED = Set{
    "as", "assert", "break", "case", "catch", "class", "const", "continue",
    "def", "default", "do", "else", "enum", "extends", "false", "final",
    "finally", "for", "if", "implements", "import", "in", "instanceof",
    "interface", "new", "null", "package", "private", "protected", "public",
    "return", "static", "super", "switch", "this", "throw", "throws", "trait",
    "true", "try", "void", "while",
  }

  RECEIVER_CALL_REGEX        = /([A-Za-z_$][A-Za-z0-9_$]*(?:(?:\s*(?:\?\.|\*\.|\.))\s*[A-Za-z_$][A-Za-z0-9_$]*)+)\s*(?:<[^;\n{}]*>)?\s*\(/
  BARE_CALL_REGEX            = /(?<![A-Za-z0-9_$.])([A-Za-z_$][A-Za-z0-9_$]*)\s*(?:<[^;\n{}]*>)?\s*\(/
  COMMAND_CALL_REGEX         = /(?:^|[;{}])\s*([A-Za-z_$][A-Za-z0-9_$]*(?:(?:\s*(?:\?\.|\*\.|\.))\s*[A-Za-z_$][A-Za-z0-9_$]*)?)\s+(?=(?:['"{\[\w$,]|\d))/
  KEYWORD_COMMAND_CALL_REGEX = /\b(?:return|throw)\s+([A-Za-z_$][A-Za-z0-9_$]*(?:(?:\s*(?:\?\.|\*\.|\.))\s*[A-Za-z_$][A-Za-z0-9_$]*)?)\s+(?=(?:['"{\[\w$,]|\d))/
  ASSIGN_CALL_REGEX          = /=\s*([A-Za-z_$][A-Za-z0-9_$]*(?:(?:\s*(?:\?\.|\*\.|\.))\s*[A-Za-z_$][A-Za-z0-9_$]*)?)\s+(?=(?:['"{\[\w$,]|\d))/

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry
    stripped_body = strip_non_code(body)

    stripped_body.each_line.with_index do |line, index|
      scan_line(line, file_path, start_line + index, entries)
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

    scan_candidates(line, RECEIVER_CALL_REGEX, candidates)
    line.scan(BARE_CALL_REGEX) do |match|
      position = match.begin(1) || 0
      next if declaration_or_constructor?(line, position)

      candidates << {position, match[1]}
    end
    scan_candidates(line, COMMAND_CALL_REGEX, candidates)
    scan_candidates(line, KEYWORD_COMMAND_CALL_REGEX, candidates)
    scan_candidates(line, ASSIGN_CALL_REGEX, candidates)

    candidates.sort_by! { |position, _| position }
    candidates.each do |_, name|
      next if skip_callee?(name)

      entries << {normalize_name(name), file_path, line_number}
    end
  end

  private def scan_candidates(line : String, regex : Regex, candidates : Array(Tuple(Int32, String)))
    line.scan(regex) do |match|
      candidates << {match.begin(1) || 0, match[1]}
    end
  end

  private def normalize_name(name : String) : String
    name.gsub(/\s+/, "").gsub("?.", ".").gsub("*.", ".")
  end

  private def skip_callee?(name : String) : Bool
    return true if name.empty?

    last = normalize_name(name).split('.').last
    RESERVED.includes?(last)
  end

  private def declaration_or_constructor?(line : String, position : Int32) : Bool
    before = line[0...position]
    return true if before.match(/\b(?:def|private|protected|public|static|final)\s+$/)
    return true if before.match(/\bnew\s+$/)

    false
  end

  private def strip_non_code(body : String) : String
    index = 0
    stripped = String::Builder.new

    while index < body.size
      char = body[index]

      if index + 1 < body.size && char == '/' && body[index + 1] == '/'
        append_blanks_until_line_end(stripped, body, index)
        index += 2
        while index < body.size && body[index] != '\n'
          index += 1
        end
        next
      end

      if index + 1 < body.size && char == '/' && body[index + 1] == '*'
        end_index = index + 2
        while end_index + 1 < body.size && !(body[end_index] == '*' && body[end_index + 1] == '/')
          end_index += 1
        end
        end_index += 2 if end_index + 1 < body.size
        append_blanks(stripped, body, index, end_index)
        index = end_index
        next
      end

      if literal_end = Noir::GroovyLiteralScanner.skip_literal(body, index)
        append_blanks(stripped, body, index, literal_end)
        index = literal_end
        next
      end

      stripped << char
      index += 1
    end

    stripped.to_s
  end

  private def append_blanks_until_line_end(stripped : String::Builder, body : String, start : Int32)
    index = start
    while index < body.size && body[index] != '\n'
      stripped << ' '
      index += 1
    end
  end

  private def append_blanks(stripped : String::Builder, body : String, start : Int32, finish : Int32)
    index = start
    while index < finish && index < body.size
      stripped << (body[index] == '\n' ? '\n' : ' ')
      index += 1
    end
  end

  private def dedup_entries(entries : Array(Entry)) : Array(Entry)
    seen = Set(Entry).new
    entries.select { |entry| seen.add?(entry) }
  end
end
