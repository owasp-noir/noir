require "../models/endpoint"
require "./callee_extractor_base"

module Noir::FsharpCalleeExtractor
  extend self
  include Noir::CalleeExtractorBase

  alias StripState = NamedTuple(block_comment_depth: Int32, triple_string: Bool)

  INITIAL_STATE = {
    block_comment_depth: 0,
    triple_string:       false,
  }

  RESERVED = Set{
    "abstract", "and", "as", "assert", "base", "begin", "class", "default",
    "delegate", "do", "done", "downcast", "downto", "elif", "else", "end",
    "exception", "extern", "false", "finally", "for", "fun", "function",
    "global", "if", "in", "inherit", "inline", "interface", "internal",
    "lazy", "let", "let!", "match", "member", "module", "mutable",
    "namespace", "new", "not", "null", "of", "open", "or", "override",
    "private", "public", "rec", "return", "return!", "select", "static",
    "struct", "then", "to", "true", "try", "type", "upcast", "use", "use!",
    "val", "void", "when", "while", "with", "yield", "yield!",
    "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS",
    "choose", "route", "routeCi", "routef", "routex", "subRoute",
    "subRouteCi", "subRoutef", "task", "async", "next", "ctx", "context",
  }

  QUALIFIED_CALL_REGEX = /(?<![A-Za-z0-9_'])((?:[A-Za-z_][A-Za-z0-9_']*)(?:\s*\.\s*[A-Za-z_][A-Za-z0-9_']+)+)(?:\s*<[^>\n]*>)?\s*(?:\(|(?=\s+(?:[A-Za-z_(@"]|\d)))/
  CHAIN_CALL_REGEX     = />=>\s*([A-Za-z_][A-Za-z0-9_']*(?:\s*\.\s*[A-Za-z_][A-Za-z0-9_']+)*)/
  PIPE_CALL_REGEX      = /\|>\s*([A-Za-z_][A-Za-z0-9_']*(?:\s*\.\s*[A-Za-z_][A-Za-z0-9_']+)*)/
  ASSIGN_CALL_REGEX    = /\b(?:let!?|use!?)\s+[A-Za-z_][A-Za-z0-9_']*(?:\s*:[^=]+)?\s*=\s*([A-Za-z_][A-Za-z0-9_']*(?:\s*\.\s*[A-Za-z_][A-Za-z0-9_']+)*)(?:\s*<[^>\n]*>)?\s*(?:\(|(?=\s+(?:[A-Za-z_(@"]|\d)))/
  RETURN_CALL_REGEX    = /\breturn!?\s+([A-Za-z_][A-Za-z0-9_']*(?:\s*\.\s*[A-Za-z_][A-Za-z0-9_']+)*)(?:\s*<[^>\n]*>)?\s*(?:\(|(?=\s+(?:[A-Za-z_(@"]|\d)))/
  PAREN_CALL_REGEX     = /[(,]\s*([A-Za-z_][A-Za-z0-9_']*)\s+(?=[A-Za-z_(@"])/
  STATEMENT_CALL_REGEX = /^\s*([A-Za-z_][A-Za-z0-9_']*(?:\s*\.\s*[A-Za-z_][A-Za-z0-9_']+)*)\b(?:\s*<[^>\n]*>)?\s*(?:$|(?=[A-Za-z_(@"]))/

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry
    state = INITIAL_STATE

    body.each_line.with_index do |line, index|
      stripped, state = strip_non_code_with_state(line, state)
      scan_line(stripped, file_path, start_line + index, entries)
    end

    dedup_entries(entries)
  end

  private def scan_line(line : String, file_path : String, line_number : Int32, entries : Array(Entry))
    candidates = [] of Tuple(Int32, String)

    scan_candidates(line, QUALIFIED_CALL_REGEX, candidates)
    scan_candidates(line, CHAIN_CALL_REGEX, candidates)
    scan_candidates(line, PIPE_CALL_REGEX, candidates)
    scan_candidates(line, ASSIGN_CALL_REGEX, candidates)
    scan_candidates(line, RETURN_CALL_REGEX, candidates)
    scan_candidates(line, PAREN_CALL_REGEX, candidates)
    scan_candidates(line, STATEMENT_CALL_REGEX, candidates)

    candidates.sort_by! { |position, _| position }
    candidates.each do |_, name|
      next if skip_callee?(name)

      entries << {name, file_path, line_number}
    end
  end

  private def scan_candidates(line : String, regex : Regex, candidates : Array(Tuple(Int32, String)))
    line.scan(regex) do |match|
      candidates << {match.begin(1) || 0, normalize_name(match[1])}
    end
  end

  private def normalize_name(name : String) : String
    name.gsub(/\s+/, "")
  end

  private def skip_callee?(name : String) : Bool
    return true if name.empty?

    last = name.split('.').last
    RESERVED.includes?(last)
  end

  private def strip_non_code_with_state(line : String, state : StripState) : Tuple(String, StripState)
    chars = line.chars
    block_comment_depth = state[:block_comment_depth]
    triple_string = state[:triple_string]
    index = 0
    stripped = String::Builder.new

    while index < chars.size
      char = chars[index]

      if block_comment_depth > 0
        if char == '(' && chars[index + 1]? == '*'
          block_comment_depth += 1
          index += 1
        elsif char == '*' && chars[index + 1]? == ')'
          block_comment_depth -= 1
          index += 1
        end
      elsif triple_string
        if triple_string_delimiter?(chars, index)
          triple_string = false
          index += 2
        end
      elsif triple_string_delimiter?(chars, index)
        triple_string = true
        index += 2
      elsif char == '/' && chars[index + 1]? == '/'
        break
      elsif char == '(' && chars[index + 1]? == '*'
        block_comment_depth += 1
        index += 1
      elsif char == '@' && chars[index + 1]? == '"'
        index = skip_verbatim_string(chars, index + 1)
      elsif char == '"'
        index = skip_string(chars, index)
      else
        stripped << char
      end

      index += 1
    end

    {stripped.to_s, {block_comment_depth: block_comment_depth, triple_string: triple_string}}
  end

  private def triple_string_delimiter?(chars : Array(Char), index : Int32) : Bool
    chars[index]? == '"' && chars[index + 1]? == '"' && chars[index + 2]? == '"'
  end

  private def skip_string(chars : Array(Char), index : Int32) : Int32
    i = index + 1
    escaping = false

    while i < chars.size
      char = chars[i]
      if escaping
        escaping = false
      elsif char == '\\'
        escaping = true
      elsif char == '"'
        return i
      end
      i += 1
    end

    chars.size - 1
  end

  private def skip_verbatim_string(chars : Array(Char), index : Int32) : Int32
    i = index + 1
    while i < chars.size
      if chars[i] == '"'
        if chars[i + 1]? == '"'
          i += 2
          next
        end
        return i
      end
      i += 1
    end

    chars.size - 1
  end
end
