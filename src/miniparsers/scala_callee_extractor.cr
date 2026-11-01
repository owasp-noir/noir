require "../models/endpoint"
require "./callee_extractor_base"
require "../minilexers/scala_lexer"

module Noir::ScalaCalleeExtractor
  extend self
  include Noir::CalleeExtractorBase

  RESERVED = Set{
    "abstract", "case", "catch", "class", "def", "do", "else",
    "extends", "false", "final", "finally", "for", "forSome",
    "if", "implicit", "import", "lazy", "match", "new", "null",
    "object", "override", "package", "private", "protected",
    "return", "sealed", "super", "this", "throw", "trait", "try",
    "true", "type", "val", "var", "while", "with", "yield",
    "println", "Some", "None", "Nil",
  }

  RECEIVER_CALL_REGEX = /([A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*)+)\s*(?:\(|\{)/
  BARE_CALL_REGEX     = /(?<![.\w])([A-Za-z_]\w*)\s*(?:\(|\{)/

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Tuple(Int32, Entry)
    lexer = Noir::ScalaLexer.new(body)
    masked_lines = lexer.masked_lines
    code = String::Builder.new
    line_offsets = [] of Int32
    offset = 0

    masked_lines.each_with_index do |stripped, index|
      line_offsets << offset
      code << stripped

      unless index == masked_lines.size - 1
        code << '\n'
        offset += stripped.size + 1
      end
    end

    scan_code(code.to_s, file_path, start_line, line_offsets, entries)
    entries.sort_by(&.[0]).map(&.[1]).uniq!
  end

  def strip_comment_preserving_strings(line : String) : String
    Noir::ScalaLexer.new(line).code_lines.first? || ""
  end

  def strip_non_code_with_state(line : String,
                                block_comment_depth : Int32,
                                in_multiline_string : Bool,
                                preserve_strings : Bool = false) : Tuple(String, Int32, Bool)
    lexer = Noir::ScalaLexer.new(line)
    result = preserve_strings ? (lexer.code_lines.first? || "") : (lexer.masked_lines.first? || "")
    {result, 0, false}
  end

  private def scan_code(code : String,
                        file_path : String,
                        start_line : Int32,
                        line_offsets : Array(Int32),
                        entries : Array(Tuple(Int32, Entry)))
    return unless code.includes?('(') || code.includes?('{')

    code.scan(RECEIVER_CALL_REGEX) do |match|
      name = normalized_name(match[1])
      next if skip_callee?(name)

      offset = call_offset(match)
      entries << {offset, {name, file_path, line_for_offset(offset, start_line, line_offsets)}}
    end

    code.scan(BARE_CALL_REGEX) do |match|
      name = match[1]
      name_start = match.begin(1) || 0
      next if dotted_receiver_continuation?(code, name_start)
      next if skip_callee?(name)

      offset = call_offset(match)
      entries << {offset, {name, file_path, line_for_offset(offset, start_line, line_offsets)}}
    end
  end

  private def call_offset(match : Regex::MatchData) : Int32
    (match.end(0) || match.begin(0) || 1) - 1
  end

  private def line_for_offset(offset : Int32, start_line : Int32, line_offsets : Array(Int32)) : Int32
    line_index = 0
    line_offsets.each_with_index do |line_offset, index|
      break if line_offset > offset

      line_index = index
    end

    start_line + line_index
  end

  private def dotted_receiver_continuation?(code : String, name_start : Int32) : Bool
    code[0...name_start].strip.ends_with?(".")
  end

  private def normalized_name(name : String) : String
    name.gsub(/\s+/, "")
  end

  private def skip_callee?(name : String) : Bool
    return true if name.empty?

    last = name.split('.').last
    RESERVED.includes?(last)
  end
end
