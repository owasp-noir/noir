require "../models/endpoint"
require "./callee_extractor_base"
require "./rust_callee_extractor_ts"

module Noir::RustCalleeExtractor
  extend self
  include Noir::CalleeExtractorBase

  # Kept as a public constant for any external caller that still
  # consults the reserved set; the active implementation lives on
  # `Noir::RustCalleeExtractorTS::RESERVED` (same contents).
  RESERVED = Noir::RustCalleeExtractorTS::RESERVED

  # Walk `body` (a function body extracted as raw text by the engine)
  # and return every callee. Internally delegates to the tree-sitter
  # extractor which walks the parsed AST instead of running per-line
  # regexes. The public signature stays identical so existing
  # analyzers don't need to change.
  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    Noir::RustCalleeExtractorTS.callees_for_body_text(body, file_path, start_line)
  end

  def strip_comment(line : String, in_block_comment : Bool = false, preserve_strings : Bool = false) : String
    stripped, _ = strip_comment_with_state(line, in_block_comment, preserve_strings)
    stripped
  end

  def strip_comment_with_state(line : String, in_block_comment : Bool, preserve_strings : Bool = false) : Tuple(String, Bool)
    in_string = false
    escaped = false
    quote = '\0'
    index = 0
    stripped = String::Builder.new

    while index < line.size
      char = line[index]
      if in_block_comment
        if char == '*' && line[index + 1]? == '/'
          in_block_comment = false
          index += 1
        end
      elsif in_string
        stripped << char if preserve_strings
        if escaped
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif char == quote
          in_string = false
        end
      elsif char == '"'
        in_string = true
        quote = char
        stripped << char if preserve_strings
      elsif char == '/' && line[index + 1]? == '/'
        return {stripped.to_s, in_block_comment}
      elsif char == '/' && line[index + 1]? == '*'
        in_block_comment = true
        index += 1
      else
        stripped << char
      end
      index += 1
    end

    {stripped.to_s, in_block_comment}
  end
end
