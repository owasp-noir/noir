require "../models/endpoint"
require "./callee_extractor_base"

module Noir::ElixirCalleeExtractor
  extend self
  include Noir::CalleeExtractorBase

  RESERVED = Set{
    "after", "alias", "and", "case", "catch", "cond", "def", "defdelegate",
    "defexception", "defguard", "defguardp", "defimpl", "defmacro",
    "defmacrop", "defmodule", "defoverridable", "defp", "defprotocol",
    "defstruct", "do", "else", "end", "false", "fn", "for", "if",
    "import", "in", "nil", "not", "or", "quote", "raise", "receive",
    "require", "rescue", "throw", "true", "try", "unless", "unquote",
    "use", "when", "with",
  }

  QUALIFIED_CALL_REGEX = /((?:(?:[A-Z]\w*|:[a-z_]\w*)(?:\.[A-Z]\w*)*\.)[a-z_]\w*[!?]?)(?:\s*\(|(?=\s+(?:[A-Za-z_:@%"{\[]|\d)))/
  BARE_CALL_REGEX      = /(?<![.\w:])([a-z_]\w*[!?]?)(?:\s*\(|(?=\s+(?:[A-Za-z_:@%"{\[]|\d)))/

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    callees_for_lines(body.lines, file_path, start_line)
  end

  def callees_for_lines(lines : Enumerable(String), file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry

    lines.each_with_index do |line, index|
      scan_line(strip_comment(line), file_path, start_line + index, entries)
    end

    dedup_entries(entries)
  end

  private def scan_line(line : String, file_path : String, line_number : Int32, entries : Array(Entry))
    # Both call patterns require either `(` or whitespace before an
    # argument-like token. Lines with neither cannot produce a callee.
    return unless line.includes?('(') || line.includes?(' ') || line.includes?('\t')

    line.scan(QUALIFIED_CALL_REGEX) do |match|
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

    # Last segment after `.` without allocating a split array.
    last = if dot = name.rindex('.')
             name[dot + 1..]
           else
             name
           end
    RESERVED.includes?(last)
  end

  # Blank string literals and drop a trailing `# …` comment. Used by the
  # callee scanner and by Elixir analyzers' block-depth counters (where
  # `do`/`fn`/`end` inside a literal must not shift nesting). Hot path:
  #
  # * No `#` and no quotes → identity return (no allocation). The walk
  #   below would rebuild an identical string.
  # * Otherwise → quote-aware rebuild that discards string contents and
  #   truncates at the first out-of-string `#`.
  def strip_comment(line : String) : String
    return line unless line.includes?('#') || line.includes?('"') || line.includes?('\'')

    in_string = false
    escaped = false
    quote = '\0'
    stripped = String::Builder.new

    line.each_char do |char|
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
        return stripped.to_s
      else
        stripped << char
      end
    end

    stripped.to_s
  end
end
