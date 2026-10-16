require "../models/endpoint"
require "./callee_extractor_base"

module Noir::RustCalleeExtractor
  extend self
  include Noir::CalleeExtractorBase

  def strip_comment(line : String, preserve_strings : Bool = false) : String
    strip_comment_with_state(line, false, preserve_strings)[0]
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
